function [xOpt, b_hat, ScoreFunctionNameList, mse, AIC, BIC, card, RunTimeS, RunTimeSname] = StabilitySelection( FolderNames, ModelParams, ReNumList, xscore)
    FileNameOut = sprintf('%s/StabilitySelection.mat', FolderNames.Results);
%     if ~exist(FileNameOut, 'file')
        ts = tic;
        load(sprintf('%s/%s.mat', FolderNames.Data, FolderNames.PriorTopology));
        load(sprintf('%s/Data.mat', FolderNames.Data), 'Timepoints', 'SpeciesNames')
        N_re = size(stoich, 2);
        [constr, PriorGraph] = ReadConstraints( FolderNames, stoich );
        
        %% perfrom cross-validation
        Ncv = 5;
        for cv = 1:Ncv
            FolderNamesCV = FolderNamesFun( FolderNames.ModelName, cv, ModelParams );
            load(sprintf('%s/Response.mat', FolderNamesCV.LinSystem))
            load(sprintf('%s/Design.mat', FolderNamesCV.LinSystem))
            load(sprintf('%s/Covar.mat', FolderNamesCV.LinSystem))
            load(sprintf('%s/%s_ComputationTime.mat', FolderNamesCV.ResultsCV, FolderNames.ModelName))
            RunTimeScv(cv, :) = mean(RunTimeS);
            
            if exist('bStdEpsM', 'var')
                [ bCV{cv}, ~, values ] = NoiseNormalization( bStdEpsM, b, indx_I, values);
            else
                [ bCV{cv}, ~, values ] = NoiseNormalization( bStdEps, b, indx_I, values);
            end
            [ values, weightsCV{cv} ] = WeightDesignForRegression( indx_I, indx_J, values, N_obs, N_re ); %  weight design
            AwCV{cv} = sparse(indx_I, indx_J, values, N_obs, N_re);
            constrWCV{cv} = constr .* weightsCV{cv}; 
            
            load(sprintf('%s/ValidationSet_cv%u.mat', FolderNamesCV.Data, cv))
            [ E, V, C, E2, C3, E12 ] = CorrectMomentsForBinomialNoise( E, V, C, E2, C3, E12, FolderNames.p );

            switch FolderNames.Gradients
                case 'FD'
                    if FolderNames.NMom == 2
                        dMom_sm = GradientsFD([E;V;C], Timepoints);
                    else
                        dMom_sm = GradientsFD(E, Timepoints);
                    end
                    b = reshape(dMom_sm, [], 1);
                case 'splines'
                    if FolderNames.NMom == 2
                        dMom_sm = GradientsSplines([E;V;C], Timepoints, ModelParams.Gradients);
                    else
                        dMom_sm = GradientsSplines(E, Timepoints, ModelParams.Gradients);
                    end
                    b = reshape(dMom_sm, [], 1);
            end
            
            [indx_I, indx_J, values, N_obs, N_re] = PrepareDesign(FolderNames, E, V, C, E2, C3, E12, stoich, 0);
            [ bvalCV{cv}, ~, values ] = NoiseNormalization( bStdEps, b, indx_I, values);
            AvalCV{cv} = sparse(indx_I, indx_J, values, N_obs, N_re);
        end

        UniqueXscore = sort(unique(xscore), 'descend'); 
        NreUni = length(UniqueXscore);
        
        ReNumListCorrected = PriorGraph.indx; % take in account prior knowledge about reactions
        mseXscore = [];
        card = [];
        Npr = length(ReNumListCorrected);
        prSet = 1:Npr;

        mseJold = 10^20;
        
        x = [];
        b_hat = [];
        for i = 1:NreUni
            IndxSet = setdiff(ReNumList(find(xscore == UniqueXscore(i))), ReNumListCorrected); % find potential set of reactions for a given score-level
            while ~isempty(IndxSet)
                jbest = 0;
                for j = 1:length(IndxSet)
                    xset = ReNumListCorrected;
                    xset(end+1) = IndxSet(j); % add one element
                    % find solution on a given set of reactions
                    xCV = zeros(length(xset), Ncv);
                    for cv = 1:Ncv
                        Aw = AwCV{cv};
                        b = bCV{cv};
                        Aval = AvalCV{cv};
                        bval = bvalCV{cv};
                        constrW = constrWCV{cv};
                        weights = weightsCV{cv};
                        
                        xCV(:, cv) = (constrW(xset) + lsqnonneg(Aw(:, xset), b - Aw(:, xset)*constrW(xset)) ./ weights(xset));
                        mseJcv(cv) = sqrt(sum(((bval - Aval(:, xset)*xCV(:, cv))).^2))/ length(bval);
                        
                        if length(find(xCV(:, cv))) < (length(xset))
                            % reaction was set to zero or set to zero some
                            % other reactions => set is not optimal
                            reFlag(cv) = 1;
                        else
                            reFlag(cv) = 0;
                        end
                    
                    end
                    
                    if sum(reFlag) > 1
                        fprintf('Bad reaction (score(%u) = %.2f): %u!!\n', i, UniqueXscore(i), xset(end));
                        mseJ = mseJold + 10^20;
                    else
                        mseJ = mean(mseJcv);
                    end
                    
                    if (mseJ < mseJold) 
                        % find/update best solution with a given score
                        xJ = zeros(N_re, 1);
                        xJ(xset) = mean(xCV, 2);
                        mseJold = mseJ;
                        jbest = j;
                    end
                end
                if jbest
                    x(:, end+1) = xJ;
                    mseXscore(end+1) = mseJold;
                    b_hat(:, end+1) = (Aval*xJ) .* bStdEps;
                    card(end+1) = length(find(xJ));
                    ReNumListCorrected(end+1) =  IndxSet(jbest);
                    IndxSet(jbest) = [];
%                     fprintf('Add %u\n', IndxSet(jbest));
                else
                    IndxSet = []; % in given set we didn't find any good reacions
                end
            end
        end

        BIC = length(b)*log(mseXscore) + log(length(b))*card;
        AIC = length(b)*log(mseXscore) + 2*card;
        mse = mseXscore;
        
        ICList = {'mse', 'BIC', 'AIC'};

        l = 0;
        for i = 1:length(ICList)
            clear indx
            indx = SelectOptimalSolution( eval(sprintf('%s', ICList{i})) );
            for j = 1:length(indx)
                l = l+1;
                ScoreFunctionNameList{l} = sprintf('%s_%u', ICList{i}, j);
                fprintf('%s optimal: \t', ScoreFunctionNameList{l});
                xOptIndx(l) = indx(j);
                xOptimal = x(:, indx(j));
                if strcmp(FolderNames.connect, 'connected') 
                    [ ~, f, ReNotConnected ] = CheckConnected( stoich, xOptimal );
                    while ~f
                        % select only one non-connected reaction
                        clear mseJre xCVm
                        for jj = 1:length(ReNotConnected)
                            xset = find(xOptimal);
                            xset(end+1) = ReNotConnected(jj); % add one element
                            % find solution on a given set of reactions
                            xCV = zeros(length(xset), Ncv);
                            for cv = 1:Ncv
                                Aw = AwCV{cv};
                                b = bCV{cv};
                                Aval = AvalCV{cv};
                                bval = bvalCV{cv};
%                                 constrW0(xset) = 1e-10 .* weights(xset);
                                constrW = constrWCV{cv};
                                constrW(xset) = max(constrW(xset), 1e-10);
                                weights = weightsCV{cv};

                                xCV(:, cv) = (constrW(xset) + lsqnonneg(Aw(:, xset), b - Aw(:, xset)*constrW(xset)) ./ weights(xset));
                                mseJcv(cv) = sum(((bval - Aval(:, xset)*xCV(:, cv))).^2);
                            end
                            xCVm(:, jj) = mean(xCV, 2);
                            mseJre(jj) = mean(mseJcv);
                        end
                        [~, ReToAdd] = min(mseJre);
                        xset = find(xOptimal);
                        xset(end+1) = ReNotConnected(ReToAdd);
                        xOptimal(xset) = xCVm(:, ReToAdd);
                        [ ~, f, ReNotConnected ] = CheckConnected( stoich, xOptimal );
                    end
                end
                xOpt(:, l) = xOptimal;
            end
        end
        
        RunTimeS = max(RunTimeScv);
        RunTimeS(end+1) = toc(ts);
        RunTimeSname{end+1} = 'StabilitySelection';
        
        save(FileNameOut, 'x', 'mse', 'AIC', 'BIC', 'ScoreFunctionNameList', 'xOpt', 'xOptIndx', 'RunTimeS', 'RunTimeSname', 'card', 'b_hat')
%     else
%         load(FileNameOut)
%     end
end



function [xOpt, imin] = OptimalSolution(x, ScoreFunction)  
    [~, imin] = min(ScoreFunction);
    xOpt = x(:, imin);
    fprintf('%u reactions\n', length(find(xOpt)));
end