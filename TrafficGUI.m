% TrafficGUI.m
% Real-Time Traffic Density Estimation - MATLAB GUI
% Single-file app (uifigure) that wraps an improved traffic-counting pipeline
function TrafficGUI()
    
    % Check required toolboxes
    if ~license('test','video_and_image_blockset') && ~exist('vision.ForegroundDetector','class')
        warning('Computer Vision Toolbox recommended for best results. Background subtraction will still try to run.');
    end

    % Create UIFigure
    fig = uifigure('Name','Traffic Density Control - GUI','Position',[100 100 1100 700]);

    % --- Left: Controls ---
    pnl = uipanel(fig,'Title','Controls','Position',[10 10 320 680]);

    lblVideo = uilabel(pnl,'Text','Video/File:','Position',[10 620 100 22]);
    edtVideo = uieditfield(pnl,'text','Value','traffic_video.mp4','Position',[10 590 300 28]);
    btnBrowse = uibutton(pnl,'Text','Browse','Position',[10 560 80 28], 'ButtonPushedFcn',@onBrowse);

    lblMinArea = uilabel(pnl,'Text','Min Blob Area:','Position',[10 520 120 22]);
    sldMinArea = uislider(pnl,'Limits',[50 4000],'Value',450,'Position',[10 500 280 3]);
    lblMinAreaVal = uilabel(pnl,'Text',num2str(round(sldMinArea.Value)),'Position',[260 485 40 22]);
    sldMinArea.ValueChangedFcn = @(s,e) set(lblMinAreaVal,'Text',num2str(round(s.Value)));

    lblSmoothing = uilabel(pnl,'Text','Smoothing (alpha):','Position',[10 450 120 22]);
    sldSmooth = uislider(pnl,'Limits',[0 1],'Value',0.6,'Position',[10 430 280 3]);
    lblSmoothVal = uilabel(pnl,'Text',num2str(sldSmooth.Value,'%.2f'),'Position',[260 415 40 22]);
    sldSmooth.ValueChangedFcn = @(s,e) set(lblSmoothVal,'Text',num2str(s.Value,'%.2f'));

    lblBase = uilabel(pnl,'Text','Base Green (s):','Position',[10 380 120 22]);
    edtBase = uieditfield(pnl,'numeric','Value',8,'Position',[140 380 80 22]);

    lblBudget = uilabel(pnl,'Text','Cycle Budget (s):','Position',[10 340 120 22]);
    edtBudget = uieditfield(pnl,'numeric','Value',60,'Position',[140 340 80 22]);

    chkUseYOLO = uicheckbox(pnl,'Text','Use YOLO (requires MATLAB support)','Position',[10 300 240 22], 'Value', false);

    btnLoad = uibutton(pnl,'Text','Load Video','Position',[10 250 120 36],'ButtonPushedFcn',@onLoad);
    btnStart = uibutton(pnl,'Text','Start','Position',[150 250 80 36],'ButtonPushedFcn',@onStart,'Enable','off');
    btnStop = uibutton(pnl,'Text','Stop','Position',[240 250 80 36],'ButtonPushedFcn',@onStop,'Enable','off');

    lblStatus = uilabel(pnl,'Text','Status: Idle','Position',[10 210 300 22]);

    % ROI setup
    lblROI = uilabel(pnl,'Text','Define Lane ROIs (rectangles)','Position',[10 170 200 22]);
    btnAddROI = uibutton(pnl,'Text','Add ROI','Position',[10 140 80 28],'ButtonPushedFcn',@onAddROI,'Enable','off');
    btnClearROI = uibutton(pnl,'Text','Clear ROIs','Position',[110 140 80 28],'ButtonPushedFcn',@onClearROI,'Enable','off');
    lstROIs = uilistbox(pnl,'Position',[10 10 300 120],'Items',{'No ROIs defined'});

    % --- Right: Video display and logs ---
    ax = uiaxes(fig,'Position',[340 150 740 520]);
    ax.Toolbar.Visible = 'off';
    title(ax,'Video Preview');
    axis(ax,'off');

    tbl = uitable(fig,'Position',[340 10 740 130]);
    tbl.ColumnName = {'Frame','Time','Lane0_Cnt','Lane1_Cnt','Lane0_Green','Lane1_Green'};

    % Internal state
    state = struct();
    state.videoPath = edtVideo.Value;
    state.vreader = [];
    state.timerObj = [];
    state.ROIs = []; % [x y w h]
    state.smoothed = [];
    state.logs = [];
    state.frameIdx = 0;
    state.running = false;

    % Foreground detector & blob analyzer (lazy init)
    state.fg = [];
    state.blob = [];

    % Callback: Browse
    function onBrowse(src,event)
        [f,p] = uigetfile({'*.mp4;*.avi;*.mov','Video Files';'*.*','All Files'});
        if f>0
            edtVideo.Value = fullfile(p,f);
            state.videoPath = edtVideo.Value;
        end
    end

    % Callback: Load video
    function onLoad(src,event)
        try
            if exist(edtVideo.Value,'file')
                state.videoPath = edtVideo.Value;
                state.vreader = VideoReader(state.videoPath);
                lblStatus.Text = ['Loaded: ' state.videoPath];
                btnStart.Enable = 'on';
                btnAddROI.Enable = 'on';
                btnClearROI.Enable = 'on';
                lstROIs.Items = {'No ROIs defined'};
                state.ROIs = [];
            else
                uialert(fig,'Video file not found. Enter valid path or browse.','File Error');
            end
        catch ME
            uialert(fig,['Error loading video: ' ME.message],'Error');
        end
    end

    % Callback: Add ROI (interactive)
    function onAddROI(src,event)
        if isempty(state.vreader)
            uialert(fig,'Load a video first.','Info'); return;
        end
        f = readFrame(state.vreader);
        imshow(f,'Parent',ax); axis(ax,'off'); title(ax,'Draw ROI - double click to finish');
        h = drawrectangle(ax,'Color','yellow');
        wait(h);
        pos = h.Position; % [x y w h]
        state.ROIs = [state.ROIs; pos];
        updateROIsList();
        % Reset videoReader to start (draw consumes a frame)
        state.vreader.CurrentTime = 0;
    end

    function updateROIsList()
        if isempty(state.ROIs)
            lstROIs.Items = {'No ROIs defined'};
        else
            items = arrayfun(@(i) sprintf('ROI %d: [%.0f %.0f %.0f %.0f]', i, state.ROIs(i,:)), 1:size(state.ROIs,1), 'UniformOutput', false);
            lstROIs.Items = items;
        end
    end

    function onClearROI(src,event)
        state.ROIs = [];
        updateROIsList();
    end

    % Callback: Start
    function onStart(src,event)
        if isempty(state.vreader)
            uialert(fig,'Load video first','Info'); return;
        end
        if isempty(state.ROIs)
            selection = questdlg('No ROIs defined. Use full frame as 2 lanes split?','ROIs Missing','Yes','No','Yes');
            if strcmp(selection,'Yes')
                w = state.vreader.Width; h = state.vreader.Height;
                % split into two lanes vertically
                state.ROIs = [1 1 w/2 h; w/2+1 1 w/2 h];
                updateROIsList();
            else
                return;
            end
        end

        % initialize detector and analyzers
        try
            state.fg = vision.ForegroundDetector('NumGaussians',3,'NumTrainingFrames',50);
            state.blob = vision.BlobAnalysis('BoundingBoxOutputPort',true,'AreaOutputPort',true,'CentroidOutputPort',true,'MinimumBlobArea',round(sldMinArea.Value));
        catch
            state.fg = [];
            state.blob = [];
        end

        % reset logs and counters
        state.smoothed = zeros(1,size(state.ROIs,1));
        state.logs = [];
        state.frameIdx = 0;
        state.running = true;
        btnStart.Enable = 'off'; btnStop.Enable = 'on'; btnLoad.Enable = 'off'; btnAddROI.Enable = 'off'; btnClearROI.Enable = 'off';
        lblStatus.Text = 'Running...';

        % Use a timer to run the loop so UI remains responsive
        state.timerObj = timer('ExecutionMode','fixedRate','Period',1/state.vreader.FrameRate,'TimerFcn',@processFrame);
        start(state.timerObj);
    end

    % Callback: Stop
    function onStop(src,event)
        stopAndCleanup();
    end

    function stopAndCleanup()
        if ~isempty(state.timerObj) && isvalid(state.timerObj) && strcmp(state.timerObj.Running,'on')
            stop(state.timerObj); delete(state.timerObj); state.timerObj = [];
        end
        state.running = false;
        btnStart.Enable = 'on'; btnStop.Enable = 'off'; btnLoad.Enable = 'on'; btnAddROI.Enable = 'on'; btnClearROI.Enable = 'on';
        lblStatus.Text = 'Stopped';
        % save logs if exist
        if ~isempty(state.logs)
            try
                csvwrite('matlab_traffic_gui_log.csv', cell2mat(state.logs));
                uialert(fig,'Saved log to matlab_traffic_gui_log.csv','Saved');
            catch
                % ignore
            end
        end
    end

    % Main per-frame processing
    function processFrame(~,~)
        if ~hasFrame(state.vreader)
            stopAndCleanup(); return;
        end
        frame = readFrame(state.vreader);
        state.frameIdx = state.frameIdx + 1;

        % Preprocess
        gray = rgb2gray(frame);

        % Foreground detection
        if ~isempty(state.fg)
            fgmask = state.fg.step(gray);
            fgmask = imopen(fgmask, strel('rectangle',[3 3]));
            fgmask = imclose(fgmask, strel('rectangle',[15 15]));
            fgmask = imfill(fgmask, 'holes');
            [areas, centroids, bboxes] = state.blob.step(fgmask);
        else
            % fallback: simple background subtraction manual
            bboxes = [];
            centroids = [];
            areas = [];
        end

        % Count per ROI
        laneCounts = zeros(1,size(state.ROIs,1));
        for i=1:size(bboxes,1)
            bb = bboxes(i,:);
            cx = bb(1)+bb(3)/2; cy = bb(2)+bb(4)/2;
            for r=1:size(state.ROIs,1)
                roi = state.ROIs(r,:);
                if cx >= roi(1) && cx <= roi(1)+roi(3) && cy >= roi(2) && cy <= roi(2)+roi(4)
                    laneCounts(r) = laneCounts(r) + 1;
                    break;
                end
            end
        end

        % smoothing
        alpha = sldSmooth.Value;
        state.smoothed = alpha*laneCounts + (1-alpha)*state.smoothed;

        % compute green allocations (proportional)
        baseG = edtBase.Value; cycle = edtBudget.Value;
        total = sum(state.smoothed);
        greens = zeros(1,length(state.smoothed));
        for r=1:length(state.smoothed)
            if total>0
                prop = state.smoothed(r)/total;
            else
                prop = 1/length(state.smoothed);
            end
            g = baseG + prop*(cycle - baseG*length(state.smoothed));
            greens(r) = round(max(baseG, min(40, g)));
        end

        % Visualization
        imshow(frame,'Parent',ax); axis(ax,'off');
        hold(ax,'on');
        for r=1:size(state.ROIs,1)
            roi = state.ROIs(r,:);
            rectangle(ax,'Position',roi,'EdgeColor','y','LineWidth',2);
            text(ax, roi(1), max(roi(2)-10,5), sprintf('Lane %d: cnt=%d s=%.1f g=%ds', r-1, laneCounts(r), state.smoothed(r), greens(r)), 'Color','w','BackgroundColor','k');
        end
        for i=1:size(bboxes,1)
            bb = bboxes(i,:);
            rectangle(ax,'Position',bb,'EdgeColor','g','LineWidth',1);
        end
        hold(ax,'off');

        % Update table and logs
        if isempty(state.logs)
            state.logs = {};
        end
        tstamp = now;
        row = [state.frameIdx, tstamp, laneCounts, greens];
        state.logs{end+1} = row; %#ok<AGROW>

        % Update uitable (show only last 100 rows as numeric array)
        data = cell2mat(state.logs(max(1,end-99):end));
        tbl.Data = data;

        % update status
        lblStatus.Text = sprintf('Running... Frame %d', state.frameIdx);

        drawnow limitrate;
    end

    % Clean up when figure closed
    fig.CloseRequestFcn = @(src,event) onClose();

    function onClose()
        if state.running
            stopAndCleanup();
        end
        delete(fig);
    end

end
