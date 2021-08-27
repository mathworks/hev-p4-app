% Copyright 2021 The MathWorks, Inc.
function [fid,rpt] = HEVReportGen(Data,Results,Author,ReportAxes,DriveCyc,Bar)
%%
% Automating HEV4 report generation
%
try
    fid         = true;
    simDate     = string(datetime('now','TimeZone','local','Format','d-MMM-y HH:mm'));
    dd          = datetime;
    reportName  = "HEVreport_" + year(dd) + month(dd) + day(dd) + "_" + hour(dd) + minute(dd) + ".docx";
    fileName    = "reportFig.jpg";
    fileName1   = "model.JPG";
    %%
    % Import report API classes
    % if ismcc || isdeployed % Make sure DOM is compilable
    makeDOMCompilable()
    % end
    import mlreportgen.dom.*
    % If application is deployed, generate path relative to temp directory
    templateName = 'HEV4Temp.dotx';
    rpt = Document(reportName,'docx', templatePath(templateName));
    open(rpt);
    %%
    % Import Chapters Info from Excel
    
    chapInfo = readtable('HEVDoc','Sheet','Chapters');
    dummy    = splitlines(string(chapInfo.Paragraph{3}));
    
    for i = 1 : numel(dummy), list{i} = dummy{i}; end
    %%
    % env. variable table
    Parameters = {'Pressure';   'Temperature';   'Wind Speed';    'Grade'};
    Value      = [Data.Pressure,Data.Temperature,Data.WindSpeed,Data.Grade]';
    Units      = {'Pa';            'K';             'm/s';        'deg'};
    envTable = table(Parameters,Value,Units);
    %%
    % vehicle Parameters
    Parameters = {'Loaded Wheel Radius';'Unloaded Wheel Radius';'Vehicle Mass';'Initial Battery SOC'};
    Value      = [Data.LoadedRadius,    Data.UnloadedRadius,     Data.Mass,     Data.BatterySOC]';
    Units      = {'m';'m';'kg';'%'};
    vehTable   = table(Parameters,Value,Units);
    %%
    % output preparation
    titleList  = ["Trace Velocity, Target, Actual (mph)";...
        "Engine/Motor Speed (RPM)";...
        "Engine/Motor Torque (Nm)";...
        "Battery Current (A)";...
        "Battery SOC";...
        "US Fuel Economy (MPGe)";...
        "TP HC Mass";...
        "TP CO Mass";...
        "TP NOx Mass";...
        "TP CO2 Mass"];
    legendList = {'target','actual';...
        'engine','motor';...
        'engine','motor'};
    
    for i = 1 : numel(titleList)
        
        plot(ReportAxes,  Results.Time{i},Results.Data{i},'linewidth', 2)
        if i <= 3
            lgd =  legend(ReportAxes,legendList{i,:});
        elseif i==4
            delete(lgd)
        end
        Bar.Value = Bar.Value + 0.02;
        pause(0.05)
        grid(ReportAxes,'on')
        exportgraphics(ReportAxes,"plot" + i + ".jpg",'Resolution',350)
    end

    cla(ReportAxes)
    %%
    
    holeID  = moveToNextHole(rpt);
    while string(holeID)~="#end#"
        switch holeID
            case "ProjectName"
                append(rpt,"HEV P4 Reference Application");
            case "Author"
                append(rpt,Author);
            case "fileName"
                append(rpt,reportName);
            case "Status"
                append(rpt,"To be validated");
            case "PublishDate"
                append(rpt,simDate);
            case "DocTitle"
                append(rpt,"Simulation Report");
            case "Abstract"
                append(rpt,chapInfo.Paragraph{1});
            case "MATLABRelease"
                append(rpt,chapInfo.Paragraph{2});
            case "Toolbox"
                append(rpt,list);
                append(rpt,PageBreak);
            case "RefApplication"
                append(rpt,chapInfo.Chapter{4});
            case "Background"
                append(rpt,chapInfo.Paragraph{4});
            case "Component"
                append(rpt,chapInfo.Paragraph{5});
                component = {'Lithium-ion battery pack','Mapped electric motor','Mapped spark-ignition (SI) engine'};
                append(rpt,component);
            case "SimulinkDiagram"
                imageObj = Image(fileName1);
                imageObj.Width = '16cm';
                imageObj.Height = '6cm';
                append(rpt,imageObj);
                append(rpt,"Hybrid Electric Vehicle P4 Reference Application");
            case "DriveCycle"
                append(rpt,Data.DriveCycleID);
            case "EngineType"
                append(rpt,Data.Engine);
            case "DriveCycleVel"
                DriveCyc.Children(1).LineWidth=1;
                exportgraphics(DriveCyc,fileName)
                pause(1)
                imageObj = Image(fileName);
                imageObj.Width = '16cm';
                imageObj.Height = '8cm';
                append(rpt,imageObj);
            case "BatteryType"
                append(rpt,"Lithium Ion");
            case "envTable"
                append(rpt,MATLABTable(envTable));
            case "vehTable"
                append(rpt,MATLABTable(vehTable));
            case "Title1"
                plotSimulation(rpt,"plot1.jpg",titleList(1))
            case "Title2"
                plotSimulation(rpt,"plot2.jpg",titleList(2))
            case "Title3"
                plotSimulation(rpt,"plot3.jpg",titleList(3))
            case "Title4"
                plotSimulation(rpt,"plot4.jpg",titleList(4))
            case "Title5"
                plotSimulation(rpt,"plot5.jpg",titleList(5))
            case "Title6"
                plotSimulation(rpt,"plot6.jpg",titleList(6))
            case "Title7"
                plotSimulation(rpt,"plot7.jpg",titleList(7))
            case "Title8"
                plotSimulation(rpt,"plot8.jpg",titleList(8))
            case "Title9"
                plotSimulation(rpt,"plot9.jpg",titleList(9))
            case "Title10"
                plotSimulation(rpt,"plot10.jpg",titleList(10))
            case "TOCPlaceHolder"
                toc = append(rpt,TOC(2));
            case "MWCopyright"
                append(rpt,"© 1994-2021 The MathWorks, Inc.");
        end
        holeID  = moveToNextHole(rpt);
        Bar.Value = min(Bar.Value + 0.03,0.99);
        pause(0.1)
    end
    
    %%
    % Close the report (required)
    close(rpt);
    %% Not available for the web app
    %     docobj = mlreportgen.utils.WordDoc(reportName);
    %     update(docobj)
    %     pdfFullPath = exportToPDF( docobj,'reportHEV.pdf');
    %     close(docobj,false)
    %    web(pdfFullPath)
    %%
%     web(rpt.OutputPath);
    %% Display the report (optional) not available for the web App
    %     rptview(reportName,'pdf');
catch
    
    fid = false;
    return
end

%% HELP FUNCTIONS

    function imageObj = imageBuild(fileName)
        
        imageObj = Image(fileName);
        imageObj.Width  = '16cm';
        imageObj.Height = '9cm';
    end

    function plotSimulation(rpt,fileName,titleList)
        
        append(rpt,titleList);
        moveToNextHole(rpt);
        imageObj = imageBuild(fileName);
        append(rpt,imageObj);
    end

    function template = templatePath(templatename)
        
        % Where's my template?
        whoAmI = mfilename('fullpath');
        [fullpath, ~, ~] = fileparts(whoAmI);
        template = fullfile(fullpath,templatename);
    end
end