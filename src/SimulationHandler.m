classdef SimulationHandler < handle
    
    events
        SimulationStarted
        SimulationPaused
        SimulationErrored
        SimulationEnded
        PastResultsLoaded
        ResultsExported
        ResultsUpdated
    end
    
    properties
        OutputNamesFile = "SimulationOutputs.xlsx"
        OutputName
        TMP % Tunable Model Parameters
        WasSimulating (1,1) logical = false
        IsPastResultsLoaded (1,1) logical = false
        Map
        PastResults
        NOutputs double {isscalar}
        Timer timer
        RefreshRate = 5
    end

    properties (SetObservable)
        ShowLive (1,1) logical = true % Live / End
        Results
        ProgressPercentage
    end
    
    properties(Access = private)
        SimIn
        ModelName
    end
    
    methods (Access = private)

        function getOutputs(obj, out)
            for i = 1:obj.NOutputs
                idx = obj.Map(out.logsout{i}.Name);
                obj.Results.Time{idx} = out.logsout{i}.Values.Time;
                OutData = squeeze(out.logsout{i}.Values.Data);
                if isequal(size(OutData,1), numel(obj.Results.Time{idx}))
                    obj.Results.Data{idx} = transpose(OutData);
                end
            end
            notify(obj, "ResultsUpdated")
        end

        function onSimulationStart(obj, ~)
            % Initialize output arrays
            for i = 1:obj.NOutputs
                obj.Results.Time{i} = [];
                obj.Results.Data{i} = [];
            end

            % Run simulation
            start(obj.Timer)
            notify(obj, "SimulationStarted")
        end % onSimulationStart

        function getTemporaryOutput(obj, ~, ~)
            % If simulation is running, collect temporary output
            switch simulink.compiler.getSimulationStatus(obj.ModelName)
                case "Running"
                    % Update time
                    obj.ProgressPercentage = simulink.compiler.getSimulationTime(obj.ModelName)/obj.TMP.EndSimulationTime*100;
                    out = simulink.compiler.getSimulationOutput(obj.ModelName);
                    getOutputs(obj, out)
            end
        end

        function startSimulationProcedures(obj)
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
            %if obj.ShowLive
            %    obj.SimIn = simulink.compiler.setExternalOutputsFcn(obj.SimIn, @obj.processOutputs);
            %end
            obj.SimIn = obj.SimIn.setPostSimFcn(@(~) obj.onSimulationEnd);
            obj.SimIn = obj.SimIn.setPreSimFcn(@(~) obj.onSimulationStart);
            
            % If repetability checkbox is on, then repeat drive cycle cyclically
            if obj.TMP.EndSimulationTime > obj.TMP.DriveCycle.Time(end)
                RepeatTimes = floor(obj.TMP.EndSimulationTime/obj.TMP.DriveCycle.Time(end));
                [~, Remainder] = min(abs(obj.TMP.DriveCycle.Time-rem(obj.TMP.EndSimulationTime,obj.TMP.DriveCycle.Time(end))));
                Time = obj.TMP.DriveCycle.Time;
                for i = 1:RepeatTimes-1
                    Time = [Time; Time(end) + obj.TMP.DriveCycle.Time]; %#ok<AGROW>
                end
                Time = [Time; Time(end) + obj.TMP.DriveCycle.Time(1:Remainder)];
                Velocity = [repmat(obj.TMP.DriveCycle.Data, RepeatTimes, 1); obj.TMP.DriveCycle.Data(1:Remainder)];
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
        end % startSimulationProcedures

        function onSimulationEnd(obj, ~)
            stop(obj.Timer)
            obj.WasSimulating = true;
            notify(obj, "SimulationEnded")
        end

    end % methods (Access = private)
    
    methods
                        
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
                save([Path, Filename], '-struct', 'Result')
                notify(obj, 'ResultsExported', NotifyData([Path, Filename]));
            else
                % User selected "Cancel" and did not specify a path
                return
            end
        end
 
        function obj = SimulationHandler   
            obj.TMP = HEVData;
            obj.ModelName = ['Hev_' obj.TMP.Engine];
            if ~isdeployed
                load_system(obj.ModelName)
            end
            % Read simulation outputs and create map container
            tab = readtable(obj.OutputNamesFile);
            obj.OutputName = tab.Name;
            obj.Map = containers.Map(tab.Name, tab.OutputNumber);
            obj.NOutputs = size(obj.Map,1);
            for i = 1:obj.NOutputs
                obj.Results.Time{i} = [];
                obj.Results.Data{i} = [];
            end

            % Define timer that collects temporary output
            obj.Timer = timer(...
                ExecutionMode = "fixedRate", ...
                Period = 0.1, ...
                TimerFcn = @obj.getTemporaryOutput);
        end
               
        function stopSimulation(obj)
            switch simulink.compiler.getSimulationStatus(obj.ModelName)
                case {"Running", "Paused"}
                    simulink.compiler.stopSimulation(obj.ModelName);
            end
        end % stopSimulation

        function toggleExecution(obj)
            switch simulink.compiler.getSimulationStatus(obj.ModelName)
                case "Inactive"
                    try
                        % Create simulation input object
                        startSimulationProcedures(obj)

                        % Run simulation
                        out = sim(obj.SimIn);
                        getOutputs(obj, out)
                    catch ME
                        stopSimulation(obj)
                        notify(obj, "SimulationErrored", NotifyData({ME.message, 'Simulation Error'}))
                    end

                case "Running"
                    simulink.compiler.pauseSimulation(obj.ModelName);
                    stop(obj.Timer)
                    notify(obj, "SimulationPaused")

                case "Terminating"
                    % Do nothing as simulation is almost finished

                case "Paused"
                    start(obj.Timer)
                    notify(obj, "SimulationStarted")
                    simulink.compiler.resumeSimulation(obj.ModelName);
            end
        end % toggleExecution
        
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

        % Update model parameter value, taking into account the status of
        % the simulation (running or idle). If running, then parameter value
        % is updated live.
        function updateSimulationParameter(obj, PropName, PropValue)
            % If simulation is running, need to pause simulation for
            % changes to take effect
            switch simulink.compiler.getSimulationStatus(obj.ModelName)
                case "Running"
                    simulink.compiler.pauseSimulation(obj.ModelName);
                    simulink.compiler.modifyParameters(obj.ModelName, ...
                        Simulink.Simulation.Variable(PropName, PropValue));
                    simulink.compiler.resumeSimulation(obj.ModelName);
                case "Paused"
                    simulink.compiler.modifyParameters(obj.ModelName, ...
                        Simulink.Simulation.Variable(PropName, PropValue));
            end

            obj.TMP.(PropName) = PropValue;
        end % updateSimParam
    end
end