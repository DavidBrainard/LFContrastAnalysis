function directionTimeCoursePacketPocket = makeDirectionTimeCoursePacketPocket(iampTimeCoursePacketPocket)
% Takes packets procuded by fit_IAMP and replaces the stimulus with
% direction and contrast for fit to the time course.
%
% Syntax:
%    directionTimeCoursePacketPocket = makeDirectionTimeCoursePacketPocket(iampTimeCoursePacketPocket)
%
% Description:
%    Takes packets procuded by fit_IAMP and replaces the existing stimulus
%    that is coded for for the IAMP model with the direction and contrast
%    stimulus need for both the Naka-Rushton and QCM models. The contrast
%    and directions information lives in the metaData subfield of the IAMP
%    packets
%
% Inputs:
%   iampTimeCoursePacketPocket - Cell array of IAMP packets from fit_IAMP
%
% Outputs:
%   directionTimeCoursePacketPocket - Cell array of packets for directions
%                                     based models such as QCM and Naka-Ruston
%
% Optional key/value pairs:
%   none

% History:
%   MAB 01/06/19                Wrote it
%   MAB, DHB  01/21/19  

for ii = 1:size(iampTimeCoursePacketPocket,1)
    for jj = 1:size(iampTimeCoursePacketPocket,2)
        
        % Get a packet
        thePacket = iampTimeCoursePacketPocket{ii,jj};
        
        % Create stimulus from meta data
        newStim = [thePacket.metaData.stimDirections; thePacket.metaData.stimContrasts];
        
        % Replace the existing stim with new stim
        thePacket.stimulus.values = newStim;
        
        directionTimeCoursePacketPocket{ii,jj} = thePacket;
    end
end

end