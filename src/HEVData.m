classdef HEVData < handle
%HEVDATA Simulation data for HEV P4 Simulink Model   
%
%   HEVData can be used to run simulations of the HEV P4 Simulink model
%   programmatically. It can also be used as part of the backend of a GUI.
%
%   Copyright 2022 The MathWorks, Inc.

    events
        DriveCycleChanged
        Error
    end
    
    properties (SetObservable)
        InitialSOC {mustBePositive, mustBeInteger, mustBeLessThanOrEqual(InitialSOC, 100)} = 60
        Engine = 'SiMappedEngine'
        Units = 'm/s'
        EndSimulationTime {mustBePositive} = 2474
    end
    
    properties
        % Environment
        Pressure    {mustBePositive} = 1
        Temperature {mustBePositive} = 300
        Grade       {mustBeGreaterThanOrEqual(Grade, 0)} = 0
        WindSpeed   {mustBeGreaterThanOrEqual(WindSpeed, 0)} = 0

        % Vehicle
        LoadedRadius   {mustBePositive} = 0.327
        UnloadedRadius {mustBePositive} = 0.336
        VehicleMass    {mustBePositive} = 1623

        % WOT
        StartTime {mustBePositive} = 5
        InSpeed   {mustBeGreaterThanOrEqual(InSpeed, 0)} = 0
        RefSpeed  {mustBePositive} = 30
        FinSpeed  {mustBeGreaterThanOrEqual(FinSpeed, 0)} = 0
        DecTime   {mustBePositive} = 20
        WOTTime   {mustBePositive} = 30
    end

    properties (SetAccess = private, Hidden)
        DriveCycleType = 'FTP75'
        DriveCycle
        DefaultDriveCycle
        BatteryParam
        BatteryTable
        SiMappedEngineTabData
        SiEngineTabData
        AllowedDriveCycles = ["FTP75", "Wide Open Throttle (WOT)", "Custom"]
        AllowedEngines = ["SiMappedEngine" "SiEngine"]
        AllowedUnits = ["m/s" "kph" "mph"]
    end

    methods
        function obj = HEVData
            %HEVData Class constructor.

            % Load default drive cycle
            if strcmp(obj.DriveCycleType, 'FTP75')
                s = load('cycleFTP75.mat');
                obj.DefaultDriveCycle.Time = s.cycleFTP75.Time;
                obj.DefaultDriveCycle.Data = s.cycleFTP75.Data;
            end
            setDriveCycle(obj, obj.DefaultDriveCycle.Time, obj.DefaultDriveCycle.Data)
            
            % Load battery parameters and update table. Engine parameters
            % were exported as a MAT file from the Simulink model because
            % they might be displayed in a Table inside a GUI
            [obj.BatteryTable, obj.BatteryParam] = readExternalArray(obj, 'Battery_param.mat', 'battery_param.xlsx');
            obj.SiEngineTabData = readExternalArray(obj, 'SiEngine_param.mat', 'SiEngine_param.xlsx');
            obj.SiMappedEngineTabData = readExternalArray(obj, 'SiMappedEngine_param.mat', 'SiMappedEngine_param.xlsx');
        end % HEVData
        
        function restore(obj)
            % Restore default property values and drive cycle
            mc = ?HEVData;
            mp = mc.PropertyList;
            for k = 1:length(mp)
                if mp(k).HasDefault
                    obj.(mp(k).Name) = mp(k).DefaultValue;
                end
            end
            % Custom default actions
            setDriveCycle(obj, obj.DefaultDriveCycle.Time, obj.DefaultDriveCycle.Data)
        end % restore
        
        function loadDriveCycle(obj, DriveCycleType)
            obj.DriveCycleType = DriveCycleType;
            switch obj.DriveCycleType
                case 'FTP75'
                    setDriveCycle(obj, obj.DefaultDriveCycle.Time, obj.DefaultDriveCycle.Data)
                    obj.Units = 'm/s';
                case 'Wide Open Throttle (WOT)'
                    generateWOTCurve(obj)
                    obj.Units = 'm/s';
                case 'Custom'
                    % Load drive cycle from file
                    try
                        [File, Path] = uigetfile({'*.mat';'*.xlsx';'*xls';'*.txt'});
                        if ~isnumeric(File)
                            [~, FileName, FileExtension] = fileparts(File);
                            switch FileExtension
                                case '.mat'
                                    s = load([Path File]);
                                    DriveCycleData = s.(FileName);
                                case {'.xls','.xlsx'}
                                    s = readtable([Path File], PreserveVariableNames=true);
                                    DriveCycleData = s.Variables;
                                case '.txt'
                                    s = readtable([Path File]);
                                    DriveCycleData = s.Variables;
                            end
                            % Update graphics objects associated with drive cyle
                            setDriveCycle(obj, DriveCycleData(:,1), DriveCycleData(:,2))
                            obj.Units = 'm/s';
                        end
                    catch ME
                        notify(obj, "Error", NotifyData({ME.message, 'Drive Cycle Loading Error'}))
                    end
                otherwise
                    error('Unknown Drive Cycle Type')
            end % switch
        end % loadDriveCycle
        
        function setDriveCycle(obj, Time, Data)

            arguments
                obj
                Time {mustBeVector, mustBeNonnegative}
                Data {mustBeVector}
            end
            obj.DriveCycle.Time = Time;
            obj.DriveCycle.Data = Data;

            notify(obj, "DriveCycleChanged")
        end % setDriveCycle
                
        function set.StartTime(obj, val)
            obj.StartTime = val;
            generateWOTCurve(obj)
        end % set.StartTime
        
        function set.WOTTime(obj, val)
            obj.WOTTime = val;
            generateWOTCurve(obj)
        end % set.WOTTime
        
        function set.DecTime(obj, val)
            obj.DecTime = val;
            generateWOTCurve(obj)
        end % set.DecTime
        
        function set.InSpeed(obj, val)
            obj.InSpeed = val;
            generateWOTCurve(obj)
        end % set.InSpeed
        
        function set.RefSpeed(obj, val)
            obj.RefSpeed = val;
            generateWOTCurve(obj)
        end % set.RefSpeed
        
        function set.FinSpeed(obj, val)
            obj.FinSpeed = val;
            generateWOTCurve(obj)
        end % set.FinSpeed   

        function set.Engine(obj, val)
            mustBeMember(val, obj.AllowedEngines) %#ok<*MCSUP> 
            obj.Engine = val;
        end

        function set.Units(obj, val)
            mustBeMember(val, obj.AllowedUnits) 
            obj.Units = val;
        end

        function set.DriveCycleType(obj, val)
            mustBeMember(val, obj.AllowedDriveCycles)  
            obj.DriveCycleType = val;
        end
    end % methods
    
    methods (Access = private)   
        function [TableData, ParValues]  = readExternalArray(~, MATFile, ExcelFile)
            ParValues = load(MATFile);
            tab = readtable(ExcelFile);
            ParamValues = cell(height(tab),1);
            for i = 1:height(tab)
                try
                    if isscalar(ParValues.(tab.Name{i})) || isvector(ParValues.(tab.Name{i}))
                        ParamValues{i} = num2str(ParValues.(tab.Name{i}));
                    else
                        dim = size(ParValues.(tab.Name{i}));
                        ParamValues{i} = char("Array of size " + dim(1) + "x" + dim(2));
                    end
                catch % The parameter described does not have an associated variable, but a value
                    ParamValues{i} = tab.Name{i};
                end
            end
            TableData = [tab.Description ParamValues];
        end % readExternalArray
        
        function generateWOTCurve(obj)
            % Initialize time and velocity arrays
            Time     = transpose(0:0.1:obj.WOTTime);
            Velocity = zeros(size(Time));
            % Calculate and set velocity
            iRise = round(obj.StartTime/0.1) + 2;
            iSet  = round(obj.DecTime/0.1) + 2;
            Velocity(1:iRise-1)  = obj.InSpeed;
            Velocity(iRise:iSet) = obj.RefSpeed;
            Velocity(iSet:end)   = obj.FinSpeed;
            % Update Drive Cycle
            setDriveCycle(obj, Time, Velocity)
        end % generateWOTCurve
    end % methods (Access = private)
end % classdef