function [analysisParams, iampTimeCoursePacketPocket, iampOBJ, iampParams, iampResponses, rawTC, fVal] = fit_IAMP(analysisParams, fullCleanData, varargin)
% Takes in the clean time series data and the analysis params and fits the IAMP model.
%
% Syntax:
%   [analysisParams, iampTimeCoursePacketPocket, iampOBJ, iampParams,
%   iampResponses, rawTC] = fit_IAMP(analysisParams, fullCleanData);
%
% Description:
%    This function takes in the clean time series data and the analysis params
%    and fits the IMAP model. This function builds a stimulus design matirx
%    based on the analysisParams (from each run of the experiemnt) and run the
%    IAMP model on the cleaned and trial sorted data.
%
% Inputs:
%    analysisParams             - Struct of important information for the
%                                 analysis
%    fullCleanData              - The cleaned time course
%
% Outputs:
%    analysisParams             - Returns analysisParams with any updates
%    iampTimeCoursePacketPocket - Cell array of IAMP packets for each run
%    iampOBJ                    - The IAMP object
%    iampParams                 - Cell array of IAMP parameter fits for each run
%    iampResponses              - Model response to each run
%    rawTC                      - Median time course for each run
% Optional key/value pairs:
%    modelOnOff                 - Convert the stim design matrix to a stim
%                                 onset and offset matrix and use this for
%                                 the regression model for the GLM
%    plotColor                  - vector for plot color
%    onset                      - Model the onset of a block as a delta
%                                 function in modelOnsetOffset case
%    midpoint                   - Model the midpoint of a block as a delta
%                                 function in modelOnsetOffset case
%    offset                     - Model the offset of a block as a delta
%                                 function in modelOnsetOffset case
%    concatAndFit               - Concatenate the runs and stim and fit
%    highpass                   - use a high pass filter on the data

% MAB 09/09/18
% MAB 01/06/19 -- changed from runIAMP_QCM to fit_IAMP and removed QCM

p = inputParser; p.KeepUnmatched = true; p.PartialMatching = false;
p.addRequired('analysisParams',@isstruct);
p.addRequired('fullCleanData',@isnumeric);
p.addParameter('modelOnOff',false,@islogical);
p.addParameter('concatAndFit',false,@islogical);
p.addParameter('onset',true,@islogical);
p.addParameter('midpoint',true,@islogical);
p.addParameter('offset',true,@islogical);
p.addParameter('plotColor',[],@isvector);
p.addParameter('highpass',false,@islogical)

p.parse(analysisParams,fullCleanData,varargin{:});

modelOnOff = p.Results.modelOnOff;
concatAndFit =  p.Results.concatAndFit;

analysisParams.numSessions = length(analysisParams.sessionFolderName);

tempTC = [];

for sessionNum = 1:analysisParams.numSessions
    
    
    % create empty packet for concat option
    if concatAndFit
        thePacket.response.values   = [];
        thePacket.response.timebase = [];
        % the stimulus
        thePacket.stimulus.timebase = [];
        thePacket.stimulus.values   = [];
        % the kernel
        thePacket.kernel = [];
        % the meta data (this is the constrast and directions)
        thePacket.metaData.stimDirections = [];
        thePacket.metaData.stimContrasts  = [];
        thePacket.metaData.lmsContrast    = [];
        
    end
    
    % Gets the path to a text file that contains the mat file names needed
    % to get the trail order information for each run.
    trialOrderDir  = fullfile(getpref(analysisParams.projectName,'projectPath'), analysisParams.projectNickname, 'DataFiles', analysisParams.expSubjID,analysisParams.sessionDate{sessionNum},analysisParams.sessionNumber{sessionNum});
    trialOrderFile = fullfile(getpref(analysisParams.projectName,'melaAnalysisPath'),'LFContrastAnalysis',analysisParams.sessionFolderName{sessionNum},'experimentFiles','dataFiles.txt');
    trialOrderFiles = textFile2cell(trialOrderFile);
    
    % Get the Directions of each session. This requires analysisParams.directionCoding to be organized
    % such that the directions are grouped per session and these groups are in the same order as the
    % sessions order
    
    % get then number of direction over all sessiosn
    analysisParams.numDirections = size(unique(analysisParams.directionCoding','rows')',2);
    
    % Get the directions and contrasts for corresponding session
    if analysisParams.numDirPerSession == analysisParams.numDirections
        directionCoding  = analysisParams.directionCoding;
        maxContrast = analysisParams.maxContrastPerDir;
    elseif analysisParams.numDirPerSession < size(unique(analysisParams.directionCoding','rows')',2)
        sPos = 1+ analysisParams.numDirPerSession*(sessionNum-1);
        ePos = (1+ analysisParams.numDirPerSession*(sessionNum-1)) + (analysisParams.numDirPerSession-1);
        directionCoding = analysisParams.directionCoding(:,sPos:ePos);
        maxContrast = analysisParams.maxContrastPerDir(sPos:ePos);
    else
        error('number of directions per session is greater than the number of total direction')
    end
    
    %% Construct the model object
    iampOBJ = tfeIAMP('verbosity','none');
    
    %% Create a cell of stimulusStruct (one struct per run)
    for jj = 1:analysisParams.numAcquisitions
        
        % identify the data param file
        dataParamFile = fullfile(trialOrderDir,trialOrderFiles{jj});
        
        % We are about to load the data param file. First silence the warning
        % for EnumerableClassNotFound. Save the warning state.
        warningState = warning();
        warning('off','MATLAB:class:EnumerableClassNotFound')
        
        % Load and process the data param file
        load(dataParamFile);
        expParams = getExpParams(dataParamFile,analysisParams.TR,'hrfOffset', false, 'stripInitialTRs', false);
        
        % restore warning state
        warning(warningState);
        
        % make timebase
        totalTime = protocolParams.nTrials * protocolParams.trialDuration * 1000;
        deltaT = analysisParams.TR*1000;
        stimulusStruct.timebase = linspace(0,totalTime-deltaT,totalTime/deltaT);
        responseStruct.timebase = stimulusStruct.timebase;
        
        % make stimulus values for IAMP
        % Stim coding: 80% = 1, 40% = 2, 20% = 3, 10% = 4, 5% = 5, 0% = 6;
        
        if modelOnOff
            stimulusStruct.values = convertBlockToOnsetOffset(expParams,analysisParams.baselineCondNum,totalTime,deltaT, 'onset', p.Results.onset,'midpoint',p.Results.midpoint,'offset',p.Results.offset);
        else
            stimulusStruct.values =  createRegressors(expParams,analysisParams.baselineCondNum,totalTime,deltaT);
        end
        
        % make stimulus values for QCM
        contrastCoding = [analysisParams.contrastCoding, 0];
        LMSContrastMat = LMSContrastValuesFromParams(expParams,contrastCoding,directionCoding,maxContrast,totalTime,deltaT);
        directionPrecision = 4;
        indDirectionDirections = round(directionCoding(1:analysisParams.theDimension,:),directionPrecision);
        LMSContrastMat(3,:) = [];
        [stimDirections,stimContrasts] = tfeQCMStimuliToDirectionsContrasts(LMSContrastMat, ...
            'zeroContrastDirection',indDirectionDirections(:,1),'precision',directionPrecision);
        
        % Set the number of instances.
        clear defaultParamsInfo
        defaultParamsInfo.nInstances = size(stimulusStruct.values,1);
        
        % Take the median across voxels
        rawTC{sessionNum,jj}.values = median(fullCleanData(:,:,(jj+((sessionNum-1)*10))),1);
        if p.Results.highpass
            rawTC{sessionNum,jj}.values = highpass(rawTC{sessionNum,jj}.values ,5/288,1/.8);
        end
        rawTC{sessionNum,jj}.timebase = stimulusStruct.timebase;
        rawTC{sessionNum,jj}.plotColor = [0,0,0];
        
        
        %%  Make the IAMP packet
        
        
        % the response
        if ~ concatAndFit
            thePacket.response.values   = rawTC{sessionNum,jj}.values;
            thePacket.response.timebase = stimulusStruct.timebase;
            % the stimulus
            thePacket.stimulus.timebase = stimulusStruct.timebase;
            thePacket.stimulus.values   = stimulusStruct.values;
            % the kernel
            thePacket.kernel = analysisParams.HRF;
            if p.Results.highpass
                thePacket.kernel.values = highpass(thePacket.kernel.values ,5/288,1/.8);
            end
            % the meta data (this is the constrast and directions)
            thePacket.metaData.stimDirections = stimDirections;
            thePacket.metaData.stimContrasts  = stimContrasts;
            thePacket.metaData.lmsContrast    = LMSContrastMat;
            
            
            % Remove 
            regressionMatrixStruct=thePacket.stimulus;
            regressionMatrixStruct = iampOBJ.applyKernel(regressionMatrixStruct,thePacket.kernel);
            regressionMatrixStruct = iampOBJ.resampleTimebase(regressionMatrixStruct,thePacket.response.timebase);
            y=thePacket.response.values';
            X=regressionMatrixStruct.values';
            numTimePoints = length(y);
            numNanPoints = sum(isnan(y));
            if any(isnan(y))
                validIdx = ~isnan(y);
                y = y(validIdx);
                X = X(validIdx,:);
            end
            
            dropBlocIndx =  find((std(regressionMatrixStruct.values').*.2) > nanstd(X));
            
            % Perform the fit
            [paramsFit,fVal(sessionNum,jj),IAMPResponses] = ...
                iampOBJ.fitResponse(thePacket,...
                'defaultParamsInfo', defaultParamsInfo, ...
                'searchMethod','linearRegression');
            
            if ~isempty(dropBlocIndx)
                paramsFit.paramMainMatrix(dropBlocIndx) = nan;
            end
            
            if numNanPoints > numTimePoints.*0.5
                paramsFit.paramMainMatrix = nan(size(paramsFit.paramMainMatrix));
            end
            
            
            iampParams{sessionNum,jj} = paramsFit;
            iampTimeCoursePacketPocket{sessionNum,jj} = thePacket;
            iampResponses{sessionNum,jj} = IAMPResponses;
            
            if isempty(p.Results.plotColor)
                iampResponses{sessionNum,jj}.plotColor = [.4,.7,.2];
            else
                iampResponses{sessionNum,jj}.plotColor = p.Results.plotColor;
            end
            
        else
            thePacket.response.values   = [thePacket.response.values rawTC{sessionNum,jj}.values];
            % the stimulus
            thePacket.stimulus.values   = [thePacket.stimulus.values stimulusStruct.values];
            % the meta data (this is the constrast and directions)
            thePacket.metaData.stimDirections = [thePacket.metaData.stimDirections stimDirections];
            thePacket.metaData.stimContrasts  = [thePacket.metaData.stimContrasts  stimContrasts];
            thePacket.metaData.lmsContrast    = [thePacket.metaData.lmsContrast LMSContrastMat];
            
        end
        
        
    end
    
    if concatAndFit
        
        deltaT = median(diff(stimulusStruct.timebase));
        concatTimebase= 0:deltaT:deltaT*length(thePacket.response.values)-1;
        thePacket.response.timebase = concatTimebase;
        thePacket.stimulus.timebase = concatTimebase;
        
        tempTC{sessionNum, 1}.values = thePacket.response.values;
        tempTC{sessionNum, 1}.timebase = concatTimebase;
        tempTC{sessionNum, 1}.plotColor = [0,0,0];
        
        % Perform the fit
        [paramsFit,fVal(sessionNum),IAMPResponses] = ...
            iampOBJ.fitResponse(thePacket,...
            'defaultParamsInfo', defaultParamsInfo, ...
            'searchMethod','linearRegression');
        
        iampParams{sessionNum,1} = paramsFit;
        iampTimeCoursePacketPocket{sessionNum,1} = thePacket;
        iampResponses{sessionNum,1} = IAMPResponses;
        
        if isempty(p.Results.plotColor)
            iampResponses{sessionNum,1}.plotColor = [.4,.7,.2];
        else
            iampResponses{sessionNum,1}.plotColor = p.Results.plotColor;
        end
    end
    
end
if concatAndFit
    rawTC = tempTC;
end
end


