% BM20A6100 Advanced Data Analysis and Machine Learning
% Practical Assignment - NASA A2
clc; close all; clearvars

%% Settings:
TrainPercentage         = 80;   % Percentage of data used for k-fold and calibration
TestPercentage          = 20;   % Percentage of data used for testing

rng(0)   % Default permutation of the train, val and test sets.

%% Column names:
ColNames = string([]);
% Create a vector of column names for the variables
for i = 1:21
    ColNames(i) = sprintf("Sensor %d", i);
end
ColNames(22) = "RUL";
VarLabels = ColNames;

%% Loading the datasets, compute RUL, split the data, cut the first 5 columns and normalize (center and scale)

% Define the variables for the modelling storage
DATA = cell(1,4);
model_DATA = cell(1, 4);

% Load the dataset, compute the RUL and add it to the dataset
for i = 1:4
    DATA{i} = RUL_fun(load(sprintf("train_FD00%d.txt", i)));
end

% Pretreatment (without normalization):
for i = 1:4
    % Take the number of units in the dataset:
    n_i = max(DATA{i}(:, 1));

    % Randomize the units which are included in the test partition:
    motor_num_i = randperm(n_i, floor(TestPercentage/100 * n_i));

    % Take the units not included in the test partition into the train one:
    model_DATA{i}.train = DATA{i}( ~ismember(DATA{i}(:,1),motor_num_i),:);
    % Take the test partition unit into the test set:
    model_DATA{i}.test = DATA{i}(ismember(DATA{i}(:,1),motor_num_i),:);
    
    % Save the RUL value as the response (Y) for each of the partitions: 
    model_DATA{i}.Ytrain = model_DATA{i}.train(:,end);
    model_DATA{i}.Ytest = model_DATA{i}.test(:,end);
    
    % Save the 1st row to know which unit, each of the entries are for:
    model_DATA{i}.testUnit = model_DATA{i}.test(:, 1);
    model_DATA{i}.trainUnit = model_DATA{i}.train(:, 1);
    
    % Cut all the other measurements from the datasets excl. sensor
    % measurements:
    model_DATA{i}.train = model_DATA{i}.train(:, 6:end-1);
    model_DATA{i}.test = model_DATA{i}.test(:, 6:end-1);
    
    % Find those sensors, which have 0 variance in the measurements and remove them:
    ind = find(var(model_DATA{i}.train) >= 1e-6); 

    % Cut the labels correspondingly:
    model_DATA{i}.VarLabels = VarLabels(ind);
    
    % Cut the dataset correspondingly:
    model_DATA{i}.train = model_DATA{i}.train(:, ind);
    model_DATA{i}.test = model_DATA{i}.test(:, ind);
end


%% PLS

% Allocate the variable for the modelled values:
plsModel = cell(1,4);

% Loop over the 4 different datasets:
for dataset = 1:4
    % Find the units belonging to the train partition:
    units = unique(model_DATA{dataset}.trainUnit);
    % Find the number of units and cut it into 1/4th (k-fold):
    nVal = floor(length(units)/4);

    % Perform PLS on all the cross-validation combinations (4):
    for kfold = 1:4
        % Take the units for the validation partition:
        valUnits = units((kfold - 1) * nVal + 1 : (kfold - 1) * nVal + nVal);

        % Split the data into the calibration and validation partitions:
        plsModel{dataset}.calibration{kfold} = model_DATA{dataset}.train(~ismember(model_DATA{dataset}.trainUnit,valUnits),:);
        plsModel{dataset}.validation{kfold} = model_DATA{dataset}.train(ismember(model_DATA{dataset}.trainUnit,valUnits),:);
        
        % Similarly for the responses:
        plsModel{dataset}.calibrationY{kfold} = model_DATA{dataset}.Ytrain(~ismember(model_DATA{dataset}.trainUnit,valUnits),:);
        plsModel{dataset}.validationY{kfold} = model_DATA{dataset}.Ytrain(ismember(model_DATA{dataset}.trainUnit,valUnits),:);
        
        % Loop over the possible number of latent variables (number of columns):
        for LV = 1:size(model_DATA{dataset}.train,2)
            % This section of the code is basically the same as in the
            % workshop 2:

            % Normalize the calibration partition (X)
            [plsModel{dataset}.calibrationN{kfold}, mu, sig] = normalize(plsModel{dataset}.calibration{kfold});
            X = plsModel{dataset}.calibrationN{kfold};

            % Normalize the validation partition with calb. mean and var (Xt)
            plsModel{dataset}.validationN{kfold} = normalize(plsModel{dataset}.validation{kfold}, "center", mu, "scale", sig);
            Xt = plsModel{dataset}.validationN{kfold};
    
            % Center the responses (Y and Yt) with calibration sets mean:
            plsModel{dataset}.calibrationYN{kfold} = plsModel{dataset}.calibrationY{kfold} - mean(plsModel{dataset}.calibrationY{kfold});
            Y = plsModel{dataset}.calibrationYN{kfold};
            plsModel{dataset}.validationYN{kfold} = plsModel{dataset}.validationY{kfold} - mean(plsModel{dataset}.calibrationY{kfold});
            Yt = plsModel{dataset}.validationYN{kfold};
    
            % Performing PLS:
            [plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.P, ... 
                plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.T, ...
                plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.Q, ...
                plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.U, ...
                plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.B, ...
                ~, ...
                plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.MSE, ...
                plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.stats] = plsregress(X, Y, LV);
    
            % Calculate R2 value:
            % Modelled responses for calibration: 
            Yfit    = [ones(size(X,1),1), X] * plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.B;
            % Squared residuals from mean:
            TSSRes  = sum((Y - mean(Y)).^2);
            % Squared residuals from model values:
            RSSRes  = sum((Y - Yfit).^2);
            % R2:
            plsModel{dataset}.ncomp{LV}.R2(kfold) = 1 - RSSRes / TSSRes;

            % Calculate Q2
            
            % Modelled responses for validation: 
            YfitT   = [ones(size(Xt,1),1), Xt] * plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.B;
            % Squared residuals from model values:
            PRESS = sum((Yt - YfitT).^2);
            % Q2:
            plsModel{dataset}.ncomp{LV}.Q2(kfold) = 1 - PRESS / TSSRes;

            % Storing for later:
            plsModel{dataset}.ncomp{LV}.B(kfold,:) = plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.B;
            
            % Check if the R2 and Q2 values are calculated in a stable
            % manner:
            plsModel{dataset}.ncomp{LV}.Q2(isnan(plsModel{dataset}.ncomp{LV}.Q2)) = 0;
            plsModel{dataset}.ncomp{LV}.Q2(find(plsModel{dataset}.ncomp{LV}.Q2==-Inf)) = 0;
            plsModel{dataset}.ncomp{LV}.meanR2 = nanmean(plsModel{dataset}.ncomp{LV}.R2');
            plsModel{dataset}.ncomp{LV}.meanQ2 = nanmean(plsModel{dataset}.ncomp{LV}.Q2'); 
        end
    end
end

%% Box plots:
% figure;
% for i = 1:4
%     subplot(2, 2, i)
%     boxplot(model_DATA{i}.train, model_DATA{i}.VarLabels);
%     title(sprintf("Box plot of dataset %d", i))
%     xtickangle(90)  
% end

%%  VIP scores

for dataset = 1:4
    % define how many LV is used
    nLV = size(model_DATA{dataset}.train,2);
    plsModel{dataset}.VIP_index = [];
    % define how many variables is included in the model
    nVar = length(model_DATA{dataset}.VarLabels);

    count = 1;

    figure;
    for LV = 1:nLV
        nPlot = ceil(sqrt(nLV));
        
        subplot(nPlot, nPlot, LV)
        hold on
        for kfold = 1:4
            % Uses the normalized PLS weights
            plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.W0 = ... 
                plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.stats.W ./  ...
                sqrt(sum(plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.stats.W.^2,1));
            
            p              = size(plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.P, 1);
            
            sumSq          = sum(plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.T.^2,1).* ...
                                sum(plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.Q.^2,1);
            % compute the VIP score
            vipScore       = sqrt(p*sum(sumSq.* ...
                (plsModel{dataset}.ncomp{LV}.KFOLD{kfold}.W0.^2),2) ./ sum(sumSq,2));
            % find which values are over 1, mark them with red
            indVIP         = find(vipScore >= 1);
            
            plsModel{dataset}.VIP_index(count, :) = zeros(1, nVar);
            plsModel{dataset}.VIP_index(count, indVIP) = 1;
            % plot the VIP scores
            scatter(1:length(vipScore),vipScore,'bx')
            scatter(indVIP,vipScore(indVIP),'rx')
            plot([1 length(vipScore)],[1 1],'--k')
            count = count + 1;
        end
        axis tight
        title("Number of LVs: " + LV)
        xlabel('Predictor Variables')
        ylabel('VIP Scores')
        xticks(1:nVar)
        xticklabels(model_DATA{dataset}.VarLabels);
        hold off
        plsModel{dataset}.VIP_index_mean = mean(plsModel{dataset}.VIP_index, 1);
    end
    sgtitle("Original dataset " + dataset + ", VIP values")
end

%% R2 - Q2
% retrieving R2 and Q2 values from the plsModel for every dataset
for dataset = 1:4
    R2 = [];
    Q2 = [];
    for kfold = 1:4
        for LV = 1:size(model_DATA{dataset}.train,2)
            R2(kfold,LV) = plsModel{dataset}.ncomp{LV}.R2(kfold);
            Q2(kfold,LV) = plsModel{dataset}.ncomp{LV}.Q2(kfold);
        end
    end
    
    figure;
    
    subplot(3, 1, 1)
    heatmap(R2);
    ylabel("K-fold");
    xlabel("No. components in the model");
    title("R2 values")
    
    subplot(3, 1, 2)
    heatmap(Q2);
    ylabel("K-fold");
    xlabel("No. components in the model");
    title("Q2 values");

    sgtitle("Original dataset " + dataset + ", R2 and Q2 values")

    subplot(3,1,3)
    plot(1:1:size(model_DATA{dataset}.train,2),mean(R2,1), 'k')
    hold on
    plot(1:1:size(model_DATA{dataset}.train,2),mean(Q2,1), 'm')
    xlabel("No. components in the model");
    title("Mean of the R^2 and Q^2 values over the k-folds")
    legend("R^2", "Q^2")
    ylim([0,1])


end

%% Coefficients
for dataset = 1:4
    coeffs = [];
    nLV = size(model_DATA{dataset}.train,2);
    figure;
    for LV = 1:nLV
        nPlot = ceil(sqrt(nLV));
        subplot(nPlot, nPlot, LV)
        hold on
        coeffs(LV, :) = mean(plsModel{dataset}.ncomp{LV}.B);
        bar(coeffs(LV, :))
        hold off
    end
end

%% 

%% Functions:

% Data loading and RUL computation:
function DATA = RUL_fun(DATA)
    % Input:    Loaded dataset
    % Output:   RUL included dataset

    % Compute the RUL for each unit present in the dataset:
    col = size(DATA, 2) + 1;    % RUL value included into the last column
    for i = 1:max(DATA(:, 1)) % Go through the engine entries
        % Find the current engine entries:
        ind = find(DATA(:, 1) == i);
        % Set the last column as the maximum of that units operating
        % cycles:
        DATA(ind, col) = max(DATA(ind, 2));
    end
    % Compute the RUL via. N. of Operating cycles - current opertating
    % cycle
    DATA(:, col) = DATA(:, col) - DATA(:, 2);
end


% Functions from example codes that were used earlier:
function T2     = t2comp(data, loadings, latent, comp)
        score       = data * loadings(:,1:comp);
        standscores = bsxfun(@times, score(:,1:comp), 1./sqrt(latent(1:comp,:))');
        T2          = sum(standscores.^2,2);
end

% SPEx
function [lev, levlim]=leveragex(T)
% INPUT:
% 	T =  X scores
% OUTPUT:
% 	lev = leverage values (X space)
%   levlim = approximation for 95 % confidence limits

lev = zeros(length(T),1);
[m,~] = size(T);
for i=1:m
    lev(i,1)=T(i,:)*inv(T'*T)*T(i,:)'+1/length(T); %#ok<MINV>
end
plot(lev,'-o');hold on
levlim=2*length(T(1,:))/length(T(:,1));
plot([1,length(T)],[levlim levlim]','-');
hold off
end

function T2varcontr    = t2contr(data, loadings, latent, comp)
score           = data * loadings(:,1:comp);
standscores     = bsxfun(@times, score(:,1:comp), 1./sqrt(latent(1:comp,:))');
T2contr         = abs(standscores*loadings(:,1:comp)');
T2varcontr      = sum(T2contr,1);
end

function Qcontr   = qcontr(data, loadings, comp)
score         = data * loadings(:,1:comp);
reconstructed = score * loadings(:,1:comp)';
residuals     = bsxfun(@minus, data, reconstructed);
Qcontr        = sum(residuals.^2);
end

function Qfac   = qcomp(data, loadings, comp)
score       = data * loadings(:,1:comp);
reconstructed = score * loadings(:,1:comp)';
residuals   = bsxfun(@minus, data, reconstructed);
Qfac        = sum(residuals.^2,2);
end