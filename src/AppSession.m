classdef AppSession < handle
    
    events
        % New session created
        NewSession
        % Pre-saved session loaded
        LoadSession
        % Session saved
        SavedSession
        % New session saved
        SavedAsSession
    end % events
    
    properties
        SessionMenu    matlab.ui.container.Menu
        NewMenu        matlab.ui.container.Menu
        LoadMenu       matlab.ui.container.Menu
        SaveMenu       matlab.ui.container.Menu
        SaveAsMenu     matlab.ui.container.Menu
        isSession = false
        Username = "User"
    end
    
    % Properties associated with session
    properties (Access = private)
        Parent matlab.ui.Figure
        SessionName
        SessionData (:,:) cell
        DefaultData (:,:) cell
        isSavedSession = false
        AppComponents
    end % Properties (Access = private)
    
    methods
        function obj = AppSession(App)
            
            % Assign parent as UIFigure
            Prop = properties(App);
            obj.Parent = App.(Prop{1});
            
            % Assign components
            for i = 2:numel(Prop)
                obj.AppComponents{i-1} = App.(Prop{i});
            end
            
            % Store initial session data
            storeCurrentSessionData(obj,'Def')
            
            % Create SessionMenu
            obj.SessionMenu = uimenu(obj.Parent);
            obj.SessionMenu.Text = 'Session';
            
            % Create NewMenu
            obj.NewMenu = uimenu(obj.SessionMenu);
            obj.NewMenu.MenuSelectedFcn = @obj.newMenuSelected;
            obj.NewMenu.Accelerator = 'N';
            obj.NewMenu.Text = 'New';
            
            % Create LoadMenu
            obj.LoadMenu = uimenu(obj.SessionMenu);
            obj.LoadMenu.MenuSelectedFcn = @obj.loadMenuSelected;
            obj.LoadMenu.Accelerator = 'L';
            obj.LoadMenu.Text = 'Load...';
            
            % Create SaveMenu
            obj.SaveMenu = uimenu(obj.SessionMenu);
            obj.SaveMenu.MenuSelectedFcn = @obj.saveMenuSelected;
            obj.SaveMenu.Text = 'Save';
            obj.SaveMenu.Accelerator = 'S';
            obj.SaveMenu.Separator = true;
            
            % Create SaveAsMenu
            obj.SaveAsMenu = uimenu(obj.SessionMenu);
            obj.SaveAsMenu.MenuSelectedFcn = @obj.saveAsMenuSelected;
            obj.SaveAsMenu.Accelerator = 'A';
            obj.SaveAsMenu.Text = 'Save As...';
                       
        end
    end
    
    methods
        
        function loadMenuSelected(obj,~,~)
            if obj.isSession
                % Want to save current session?
                Answer = saveSessionWithConfirm(obj);
                if strcmp(Answer,'Cancel')
                    return
                else
                    loadSavedSession;
                end
            else
                obj.isSession = loadSavedSession;
            end
            
            function isLoaded = loadSavedSession
                % import data
                % Select session file
                [File, Path] = uigetfile('*.mat');
                if ~isnumeric([Path, File])
                    if isValidSession(obj,[Path File])
                        % Load session
                        s = load([Path File]);
                        obj.SessionData = s.Data;
                        obj.SessionName = File;
                        obj.isSavedSession = true;
                        % Update graphic components that depend on session data
                        updateGraphicsComponents(obj)
                        isLoaded = true;
                        notify(obj, "LoadSession", NotifyData([Path File]))
                    end
                else
                    % User selected "Cancel" and did not specify a path
                    isLoaded = false;
                    return
                end
            end % loadSaveSession
        end % loadMenuSelected
        
        function newMenuSelected(obj,~,~)
            if obj.isSession
                % Want to save current session?
                Answer = saveSessionWithConfirm(obj);
                if strcmp(Answer,'Cancel')
                    return
                else
                    obj.SessionData = obj.DefaultData;
                    obj.isSavedSession = false;
                    updateGraphicsComponents(obj)
                    notify(obj,"NewSession")
                end
            else
                obj.SessionData = obj.DefaultData;
                notify(obj,"NewSession")
                obj.isSession = true;
            end
        end
    end
    
    methods (Access = private)
        
        % Get property name to assign value according to selected app component
        function Prop = getPropName(~, Comp)
            switch Comp
                case {'matlab.ui.control.NumericEditField'
                        'matlab.ui.control.EditField'
                        'matlab.ui.control.DropDown'
                        'matlab.ui.control.Slider'
                        'matlab.ui.control.Spinner'
                        'matlab.ui.control.RadioButton'
                        'matlab.ui.control.ListBox'
                        'matlab.ui.control.DatePicker'
                        'matlab.ui.control.CheckBox'
                        'matlab.ui.control.StateButton'
                        'matlab.ui.control.Switch'}
                    Prop = {'Value'};
                case {'matlab.ui.control.Label'}
                    Prop = {'Text' 'Visible'};
                case {'matlab.ui.control.Lamp'}
                    Prop = {'Color', 'Visible'};
                case {'matlab.ui.control.Table'}
                    Prop = {'Data'};
                case {'SimulationHandler'}
                    Prop = {'TMB'}; % Tunable Model Parameters
                case {'matlab.ui.control.Button'}
                    Prop = {'Enable'};
                otherwise
                    Prop = '';
            end
        end
        
        % Assign property value stored in session data to app component
        function updateGraphicsComponents(obj)
            for i = 1:numel(obj.AppComponents)
                Prop = getPropName(obj, class(obj.AppComponents{i}));
                if ~isempty(Prop)
                    for j = 1:numel(Prop)
                        obj.AppComponents{i}.(Prop{j}) = obj.SessionData{i,j};
                    end
                end
            end
        end
        
        % Save session data from current app components' values
        function storeCurrentSessionData(obj, Status)
            for i =1:numel(obj.AppComponents)
                Prop = getPropName(obj, class(obj.AppComponents{i}));
                if ~isempty(Prop)
                    for j = 1:numel(Prop)
                        switch Status
                            case 'Def'
                                obj.DefaultData{i,j} = obj.AppComponents{i}.(Prop{j});
                            case 'Now'
                                obj.SessionData{i,j} = obj.AppComponents{i}.(Prop{j});
                        end
                    end
                end
            end
        end
                
        % Overwrite saved session
        function saveMenuSelected(obj,~,~)
            saveSession(obj)
        end
        
        % Save new session
        function saveNewSession(obj)
            [Filename, Path] = uiputfile('*.mat',[],'NewSession.mat');
            if ~isnumeric([Path, Filename])
                obj.SessionName = [Path Filename];
                saveCurrentSession(obj)
                notify(obj, "SavedAsSession", NotifyData([Path Filename]))
            else
                % User selected "Cancel" and did not specify a path
                return
            end
        end
        
        % Check if selected file is a valid session
        function Check = isValidSession(obj,File)
            % Define message title for error window
            Title = "Invalid Session File";
            
            % Load file and extract fields
            var = load(File);
            Fields = fields(var);
            
            % Add requirements below
            % Example: numel(Fields == 1); Error message: Number of fields
            % must be 1.
            Check = numel(Fields) == 1;
            if ~Check
                uialert(obj.Parent, "Number of fields must be 1.", Title, Icon='error')
                return
            end
        end % isValidSession
        
        function Answer = saveSessionWithConfirm(obj)
            % Ask to save current session and call saveSession if answer is yes
            Answer = uiconfirm(obj.Parent,...
                'Save current session?',...
                'Save Session', 'Options', {'Yes','No','Cancel'},...
                'DefaultOption', 1, 'CancelOption', 3);
            switch Answer
                case 'Cancel'
                    return
                case 'Yes'
                    saveSession(obj)
            end
        end % saveSessionWithConfirm
        
        function saveSession(obj)
            if obj.isSavedSession
                % Save to current filename
                saveCurrentSession(obj)
                notify(obj, "SavedSession")
            else
                % Session is unsaved
                saveNewSession(obj);
            end
        end % saveSession
        
        function saveCurrentSession(obj)
            
            storeCurrentSessionData(obj,'Now');
            Data = obj.SessionData;
            save(obj.SessionName,'Data')
            obj.isSavedSession = true;
        end % saveCurrentSession
        
        function saveAsMenuSelected(obj,~,~)
            saveNewSession(obj)
        end
               
    end % methods (Access = private)
    
end