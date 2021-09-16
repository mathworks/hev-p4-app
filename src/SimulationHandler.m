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
        TMB % Tunable Model Parameters
        IsSimulating = false
        WasSimulating = false
        IsPastResultsLoaded = false
        ProgressPercentage
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
            switch obj.TMB.Engine
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
            if obj.TMB.EndSimulationTime > obj.TMB.DriveCycle.Time(end)
                RepeatTimes = floor(obj./obj.TMB.DriveCycle.Data(end));
                [~, Remainder] = min(abs(obj.TMB.DriveCycle.Time-rem(obj.TMB.EndSimulationTime,obj.TMB.DriveCycle.Time(end))));
                Time = obj.TMB.DriveCycle.Time;
                for i = 1:dum-1
                    Time = [Time; Time(end) + obj.TMB.DriveCycle.Time]; %#ok<AGROW>
                end
                Time = [Time; Time(end) + obj.TMB.DriveCycle.Time(1:dum1)];
                Velocity = [repmat(obj.TMB.DriveCycle.Data,RepeatTimes,1); obj.TMB.DriveCycle.Data(1:Remainder)];
            else
                Time = obj.TMB.DriveCycle.Time;
                Velocity = obj.TMB.DriveCycle.Data;
            end

            switch obj.TMB.Units
                case 'km/h'
                    Velocity = Velocity*0.277778;
                case 'mph'
                    Velocity = Velocity*0.44704;
            end
            
            % Load drive cycle as external input to the model
            obj.SimIn.ExternalInput = [Time Velocity];
            
            % Set simulation end time
            obj.SimIn = obj.SimIn.setModelParameter('StopTime',num2str(obj.TMB.EndSimulationTime));
            % Set environment parameters
            obj.SimIn = obj.SimIn.setVariable('Pressure',obj.TMB.Pressure*101325,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('Temperature',obj.TMB.Temperature,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('Grade',obj.TMB.Grade,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('WindSpeed',obj.TMB.WindSpeed,'Workspace', obj.ModelName);
            % Set vehicle parameters
            obj.SimIn = obj.SimIn.setVariable('LoadedRadius',obj.TMB.LoadedRadius,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('UnloadedRadius',obj.TMB.UnloadedRadius,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('VehicleMass',obj.TMB.VehicleMass,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('InitialCapacity',obj.TMB.InitialSOC*0.053,'Workspace', obj.ModelName);
            obj.SimIn = obj.SimIn.setVariable('InitialVoltage',...
                obj.TMB.BatteryParam.('Ns')*...
                interp1(obj.TMB.BatteryParam.('CapLUTBp'),...
                obj.TMB.BatteryParam.('Em'),...
                obj.TMB.InitialSOC/100),'Workspace', obj.ModelName);
            
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
            obj.ProgressPercentage = ceil(Time/obj.TMB.EndSimulationTime*100);
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
            obj.TMB = HEVData;
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
            restore(obj.TMB)
            obj.IsSimulating = false;
            obj.WasSimulating = false;
            obj.IsPastResultsLoaded = false;
            obj.ProgressPercentage = 0;
            obj.PastResults.Time = [];
            obj.PastResults.Data = [];
            for i = 1:obj.NOutputs
                obj.Results.Time{i} = 0;
                obj.Results.Data{i} = 0;
            end
            obj.ShowLive = true;
            obj.SimIn = [];
        end                
    end
end