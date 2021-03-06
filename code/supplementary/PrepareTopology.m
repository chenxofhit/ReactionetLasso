function [stoich, RunTimeS, RunTimeName ] = PrepareTopology( FolderNames )
% ModelName - Name for the model output
    RunTimeName = 'PrepareTopology';
    fprintf('%s...\n', RunTimeName);
    
    tic
    FileName = sprintf('%s/%s.mat', FolderNames.Data, FolderNames.PriorTopology);
    FileNameCompartment = sprintf('%s/CompartmentList.mat', FolderNames.Data);
    
    if ~exist(FileName, 'file') || ~strcmp(FolderNames.PriorTopology, 'Topology')
        load(sprintf('%s/Data.mat', FolderNames.Data), 'SpeciesNames')
        if exist(FileNameCompartment, 'file')
            load(FileNameCompartment)
            stoich = GenerateMetaTopology(SpeciesNames, CompartmentList);
            save(FileName, 'stoich', 'RunTimeS')
        elseif strcmp(FolderNames.PriorTopology, 'Topology')
            N_sp = length(SpeciesNames);
            G = ones(N_sp, N_sp);
            stoich = GenerateMetaTopologyFromDGraphWithInhibition(SpeciesNames, G);
            RunTimeS = 0;
            save(FileName, 'stoich', 'RunTimeS')
            
        else
            load(FileName)
            stoich = GenerateMetaTopologyFromDGraphWithInhibition(SpeciesNames, G);
            save(FileName, '-append', 'stoich')
        end
        RunTimeS = toc;
        
    else
        load(FileName)
    end
end

