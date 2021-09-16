classdef HEVData < matlab.mixin.SetGet
    
    events
        DriveCycleChanged
        Error
    end
    
    properties (SetObservable)
        InitialSOC = 60
        %
        Engine = 'SiMappedEngine'
        Units = 'm/s'
        EndSimulationTime = 2474
    end
    
    properties
        % Environment
        Pressure = 1
        Temperature = 300
        Grade = 0
        WindSpeed = 0
        % Vehicle
        LoadedRadius = 0.327
        UnloadedRadius = 0.336
        VehicleMass = 1623
        % WOT
        StartTime = 5
        InSpeed = 0
        RefSpeed = 30
        FinSpeed = 0
        DecTime = 20
        WOTTime = 30
        %
        DriveCycle
        DefaultDriveCycle
        DriveCycleType = 'FTP75'
        %
        BatteryParam
        BatteryTable
        SiMappedEngineTabData
        SiEngineTabData
    end
    
    methods
        function obj = HEVData
            % Load default drive cycle
            s = load('cycleFTP75.mat');
            obj.DefaultDriveCycle.Time = s.cycleFTP75.Time;
            obj.DefaultDriveCycle.Data = s.cycleFTP75.Data;
            setDriveCycle(obj, obj.DefaultDriveCycle.Time, obj.DefaultDriveCycle.Data)
            
            % Load battery parameters and update table
            [obj.BatteryTable, obj.BatteryParam] = readExternalArray(obj, 'Battery_param.mat', 'battery_param.xlsx');
            obj.SiEngineTabData = readExternalArray(obj, 'SiEngine_param.mat', 'SiEngine_param.xlsx');
            obj.SiMappedEngineTabData = readExternalArray(obj, 'SiMappedEngine_param.mat', 'SiMappedEngine_param.xlsx');
        end
        
        function restore(obj)
            mc = ?HEVData;
            mp = mc.PropertyList;
            for k = 1:length(mp)
                if mp(k).HasDefault
                    obj.(mp(k).Name) = mp(k).DefaultValue;
                end
            end
            % Custom default actions
            setDriveCycle(obj, obj.DefaultDriveCycle.Time, obj.DefaultDriveCycle.Data)
        end
        
        function loadDriveCycle(obj, DriveCycleType)
            obj.DriveCycleType = DriveCycleType;
            switch obj.DriveCycleType
                case 'FTP75'
                    setDriveCycle(obj, obj.DefaultDriveCycle.Time, obj.DefaultDriveCycle.Data)
                    obj.Units = 'm/s';
                case 'Wide Open Throttle (WOT)'
                    mc = ?HEVData;
                    mp = mc.PropertyList;
                    for k = 1:length(mp)
                        switch mp(k).Name
                            case {'StartTime','WOTTime','DecTime','InSpeed',...
                                    'RefSpeed','FinSpeed'}
                                obj.(mp(k).Name) = mp(k).DefaultValue;
                        end
                    end
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
                    % Do nothing
            end
        end % function loadDriveCycle
        
        function setDriveCycle(obj, Time, Data)
            % Validate arguments
            arguments
                obj
                Time {mustBeVector, mustBeNonnegative}
                Data {mustBeVector}
            end
            obj.DriveCycle.Time = Time;
            obj.DriveCycle.Data = Data;

            notify(obj, "DriveCycleChanged")
        end
                
        function set.StartTime(obj, val)
            obj.StartTime = val;
            generateWOTCurve(obj)
        end
        
        function set.WOTTime(obj, val)
            obj.WOTTime = val;
            generateWOTCurve(obj)
        end
        
        function set.DecTime(obj, val)
            obj.DecTime = val;
            generateWOTCurve(obj)
        end
        
        function set.InSpeed(obj, val)
            obj.InSpeed = val;
            generateWOTCurve(obj)
        end
        
        function set.RefSpeed(obj, val)
            obj.RefSpeed = val;
            generateWOTCurve(obj)
        end
        
        function set.FinSpeed(obj, val)
            obj.FinSpeed = val;
            generateWOTCurve(obj)
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
        end
        
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
        end
    end % methods (Access = private)
end