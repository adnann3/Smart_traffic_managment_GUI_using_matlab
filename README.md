# Smart_traffic_managment_GUI_using_matlab
This project implements a real-time traffic monitoring and adaptive signal control system using MATLAB. It processes traffic video input to estimate vehicle density across multiple lanes and dynamically adjusts signal timings based on congestion levels. Built using an interactive GUI (uifigure), the system allows users to load videos, define lane-wise regions of interest (ROIs), and visualize results in real time. The core approach uses computer vision techniques such as foreground detection (background subtraction), morphological filtering, and blob analysis to detect and count vehicles. A smoothing mechanism ensures stable density estimation, and signal timings are allocated proportionally within a fixed cycle budget, simulating intelligent traffic control used in smart city systems.

Key Features:

* Real-time traffic video processing with GUI interface
* ROI-based lane detection and customization
* Vehicle detection using background subtraction and blob analysis
* Lane-wise vehicle counting with centroid mapping
* Adaptive traffic signal timing based on density
* Smoothing algorithm to reduce detection noise
* Live visualization with bounding boxes and lane statistics
* Automatic logging and CSV export for analysis

Real-Time Effects & Output:

* Live display of detected vehicles with bounding boxes
* Dynamic update of vehicle count and density per lane
* Real-time adjustment of green signal timing based on traffic conditions
* Continuous frame-by-frame data logging and monitoring
* Visual feedback for traffic flow optimization

This project demonstrates practical applications of computer vision, DSP, and intelligent transportation systems, and can be extended for smart traffic management, IoT-based monitoring, and automated signal control solutions.
