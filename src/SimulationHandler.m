classdef SimulationHandler < handle
    
    events
        SimulationStarted
        SimulationEnded
        PastResultsLoaded
        ResultsExported
        Error
    end
    
    properties
        OutputNamesFile = "SimulationOutputs.xlsx"
        OutputName
        TMP % Tunable Model Parameters
        IsSimulating = false
        WasSimulating = false
        IsPastResultsLoaded = false
        ProgressPercentage = 0
        Map
        PastResults
        Results
        NOutputs
    end

    properties (SetObservable)
        ShowLive = true % Live / End
    end
    
    properties(Access = private)
        SimIn
        ModelName
    end
    
    methods (Access = private)
        
        function startSimulationProcedures(obj)
            obj.IsSimulating = true;
            
            %%
            % Select which model to simulate. The model name needs to be
            % passed explicitly to the simulation input object. Each case
            % selects the same model with a different variant selected (the
            % vehicle engine)
            switch obj.TMP.Engine
                case 'SiEngine'
                    obj.ModelName = 'Hev_SiEngine';
                    obj.SimIn = Simulink.SimulationInput('Hev_SiEngine');
                case 'SiMappedEngine'
                    obj.ModelName = 'Hev_SiMappedEngine';
                    obj.SimIn = Simulink.SimulationInput('Hev_SiMappedEngine');
            end
            
            % If the user wants to see results while simulation is running
            if obj.ShowLive
                obj.SimIn = simulink.compiler.setExternalOutputsFcn(obj.SimIn, @obj.processOutputs);
            end
            
            % If repetability checkbox is on, then repeat drive cycle cyclically
            if obj.TMP.EndSimulationTime > obj.TMP.DriveCycle.Time(end)
                RepeatTimes = floor(obj./obj.TMP.DriveCycle.Data(end));
                [~, Remainder] = min(abs(obj.TMP.DriveCycle.Time-rem(obj.TMP.EndSimulationTime,obj.TMP.DriveCycle.Time(end))));
                Time = obj.TMP.DriveCycle.Time;
                for i = 1:dum-1
                    Time = [Time; Time(end) + obj.TMP.DriveCycle.Time]; %#ok<AGROW>
                end
                Time = [Time; Time(end) + obj.TMP.DriveCycle.Time(1:dum1)];
                Velocity = [repmat(obj.TMP.DriveCycle.Data,RepeatTimes,1); obj.TMP.DriveCycle.Data(1:Remainder)];
            else
                Time = obj.TMP.DriveCycle.Time;
                Velocity = obj.TMP.DriveCycle.Data;
            end

            switch obj.TMP.Units
                case 'km/h'
                    Velocity = Velocity*0.277778;
                case 'mph'
                    Velocity = Velocity*0.44704;
            end
            
            % Load drive cycle as external input to the model
            obj.SimIn.ExternalInput = [Time Velocity];
            
            % Set simulation end time
            obj.SimIn = obj.SimIn.setModelParameter('StopTime',num2str(obj.TMP.EndSimulationTime));
            % Set environment parameters
            obj.SimIn = obj.SimIn.setVariable('Pressure',obj.TMP.Pressure*101325,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('Temperature',obj.TMP.Temperature,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('Grade',obj.TMP.Grade,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('WindSpeed',obj.TMP.WindSpeed,'Workspace', obj.ModelName);
            % Set vehicle parameters
            obj.SimIn = obj.SimIn.setVariable('LoadedRadius',obj.TMP.LoadedRadius,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('UnloadedRadius',obj.TMP.UnloadedRadius,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('VehicleMass',obj.TMP.VehicleMass,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('InitialCapacity',obj.TMP.InitialSOC*0.053,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('InitialVoltage',...
                obj.TMP.BatteryParam.('Ns')*...
                interp1(obj.TMP.BatteryParam.('CapLUTBp'),...
                obj.TMP.BatteryParam.('Em'),...
                obj.TMP.InitialSOC/100),'Workspace', obj.ModelName);
            
            %%
            % Configure for deployment
            obj.SimIn = simulink.compiler.configureForDeployment(obj.SimIn);
            
            % Initialize output arrays
            for i = 1:obj.NOutputs
                obj.Results.Time{i} = [];
                obj.Results.Data{i} = [];
            end
            notify(obj, "SimulationStarted")
        end
        
        function endSimulationProcedures(obj)
            obj.ProgressPercentage = 0;
            obj.WasSimulating = true;
            obj.IsSimulating = false;
            notify(obj, "SimulationEnded")
        end
                        
        function processOutputs(obj, opIdx, Time, Data)
            obj.Results.Time{opIdx} = [obj.Results.Time{opIdx} Time];
            obj.Results.Data{opIdx} = [obj.Results.Data{opIdx} Data];
            obj.ProgressPercentage = ceil(Time/obj.TMP.EndSimulationTime*100);
        end
    end % methods (Access = private)
    
    methods
                
        function startOrStopSimulation(obj)
            if obj.IsSimulating
                stop(obj)
            else
                start(obj)
            end
        end
        
        function resetResults(obj)
            % Initialize output arrays
            for i = 1:obj.NOutputs
                obj.Results.Time{i} = [];
                obj.Results.Data{i} = [];
                obj.PastResults.Time{i} = [];
                obj.PastResults.Data{i} = [];
            end
            obj.WasSimulating = false;
            obj.IsPastResultsLoaded = false;
        end % resetResults
                        
        function loadResults(obj)
            % Select session file
            [File, Path] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select a File');
            
            if ~isnumeric([Path, File])
                % Load mat file
                s = load([Path File]);
                obj.PastResults.Time = s.Time;
                obj.PastResults.Data = s.Data;
                
                obj.IsPastResultsLoaded = true;
                notify(obj, "PastResultsLoaded", NotifyData(File))
            end
        end
        
        function exportResults(obj)
            % Enter file name and choose where to save
            [Filename, Path] = uiputfile({'*.mat', 'MAT-files (*.mat)'},...
                [], 'NewSimulationResults');
            
            if ~isnumeric([Path, Filename])
                % Save to a mat file
                Result = obj.Results;
                save([Path, Filename],'-struct','Result')
                notify(obj, 'ResultsExported', NotifyData([Path, Filename]));
            else
                % User selected "Cancel" and did not specify a path
                return
            end
        end
 
        function obj = SimulationHandler   
            obj.TMP = HEVData;
            % Read simulation outputs and create map container
            tab = readtable(obj.OutputNamesFile);
            obj.OutputName = tab.Name;
            obj.Map = containers.Map(tab.Name, tab.OutputNumber);
            obj.NOutputs = size(obj.Map,1);
            for i = 1:obj.NOutputs
                obj.Results.Time{i} = [];
                obj.Results.Data{i} = [];
            end
        end
        
        function start(obj)
            try
                startSimulationProcedures(obj)
                if obj.ShowLive
                    sim(obj.SimIn);
                else
                    out = sim(obj.SimIn);
                    for i = 1:obj.NOutputs
                        idx = obj.Map(out.logsout{i}.Name);
                        obj.Results.Time{idx} = out.logsout{i}.Values.Time;
                        obj.Results.Data{idx} = transpose(out.logsout{i}.Values.Data);
                    end
                end
            catch ME
                notify(obj, "Error", NotifyData({ME.message, 'Simulation Error'}))
            end
            endSimulationProcedures(obj)
        end
        
        function stop(obj)
            simulink.compiler.stopSimulation(obj.ModelName);
            endSimulationProcedures(obj)
        end
        
        function restore(obj)
            
            restore(obj.TMP)
            
            mc = ?SimulationHandler;
            mp = mc.PropertyList;
            for k = 1:length(mp)
                if mp(k).HasDefault
                    obj.(mp(k).Name) = mp(k).DefaultValue;
                end
            end

        end                
    end
end