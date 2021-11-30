classdef tHEVApp < matlab.uitest.TestCase

    properties
        App
    end

    methods (TestClassSetup)
        function launchApp(t)
            t.App = HEVApp;
            t.addTeardown(@delete,t.App);
        end
    end

    methods (Test)
        function onNewSession(t)            
            t.press(t.App.NewSessionButton);

            strMsg = " tab is not visible";

            % Verify tabs are visible
            t.verifyNotEmpty(t.App.DriveCycleSetupTab.Parent, "Drive cycle setup" + strMsg);
            t.verifyNotEmpty(t.App.ModelParametersSetupTab.Parent, "Model parameters setup" + strMsg);
            t.verifyNotEmpty(t.App.SimulationandVisualizationTab.Parent, "Simulation and visualization" + strMsg);
            t.verifyNotEmpty(t.App.SessionLogTab.Parent, "Session Log" + strMsg);

            % Verify report tab is not visible
            t.verifyEmpty(t.App.ReportTab.Parent, "Report tab is visible");

            % Verify Drive Cycle Tab is selected
            t.verifyEqual(t.App.TabGroup.SelectedTab.Title, 'Drive Cycle Setup', "Selected tab is not Drive Cycle Setup")

        end

        function onWOTDriveCycleSelected(t)
            t.choose(t.App.DriveCycleFromDropDown, "Wide Open Throttle (WOT)");

            % Verify Wide Open Throttle Panel is visible
            t.verifyTrue(t.App.WideOpenThrottleWOTPanel.Visible)
        end

    end
    
end