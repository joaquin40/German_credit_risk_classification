## -----------------------------------------------------------------------------------------------
knitr::purl("german_credit_predictions.Rmd")


## -----------------------------------------------------------------------------------------------
pacman::p_load(tidyverse, DataExplorer, janitor, skimr, h2o, doParallel,caret, pROC, tune, pROC,
               xgboost)


## -----------------------------------------------------------------------------------------------
localH2o <- h2o.init()


## -----------------------------------------------------------------------------------------------
df_credit <- read_rds("./data/german_credit_clean.csv")


## -----------------------------------------------------------------------------------------------
df_credit


## -----------------------------------------------------------------------------------------------
skim(df_credit)


## -----------------------------------------------------------------------------------------------
DataExplorer::plot_missing(df_credit)


## -----------------------------------------------------------------------------------------------
df_credit_01 <- model.matrix(credit_class ~., data = df_credit)[,-1] |> 
  data.frame() |> 
  cbind(df_credit[,1]) |> 
  rename("credit_class" = "df_credit[, 1]") |> 
  select(credit_class, everything()) |> 
  janitor::clean_names()


## -----------------------------------------------------------------------------------------------
# df_credit_01


## -----------------------------------------------------------------------------------------------
skim(df_credit_01)
DataExplorer::plot_missing(df_credit_01)


## -----------------------------------------------------------------------------------------------
set.seed(1)

index <- createDataPartition(df_credit_01$credit_class, p=.7, list = FALSE)
training <- df_credit_01[index,]
test <- df_credit_01[-index,]

# validation
index2 <- createDataPartition(training$credit_class, p=0.7, list = FALSE)
train <- training[index2,]
validation <- training[-index2,]



## -----------------------------------------------------------------------------------------------
table(df_credit_01$credit_class)

table(training$credit_class)
table(validation$credit_class)
table(test$credit_class)



## -----------------------------------------------------------------------------------------------
table(test$credit_class)
max(table(test$credit_class)) / (table(test$credit_class) |> sum())



## -----------------------------------------------------------------------------------------------
train.hex <- as.h2o(train, destination_frame = "train.hex")
validation.hex <- as.h2o(validation, destination_frame = "validation.hex")
test.hex <- as.h2o(test, destination_frame = "test.hex")

class(test.hex)


## -----------------------------------------------------------------------------------------------
response <- "credit_class"
predictors <- colnames(train)
predictors <- predictors[!(predictors %in% response)]



## -----------------------------------------------------------------------------------------------
model <- h2o.automl(
  x = predictors,
  y = response,
  training_frame = train.hex,
  validation_frame = validation.hex,
  max_runtime_secs = 5400)
  
#   stopping_metric = "AUC",
#   max_models = 20,
#   stopping_tolerance = 0.001,
#   nfolds = 5,
#   seed = 1
# )

model



## -----------------------------------------------------------------------------------------------
# ?h2o.automl


## -----------------------------------------------------------------------------------------------
h2o.get_leaderboard(model)
fit <- model@leader

# save the model
# h2o.saveModel(fit, path = "C:/Users/sanch/Desktop/github/German Credit Data/model/StackedEnsemble_BestOfFamily_8_AutoML_21_20240121_140230",force = TRUE)




## -----------------------------------------------------------------------------------------------
auc <- h2o.auc(fit, train = FALSE, xval = TRUE); auc


## -----------------------------------------------------------------------------------------------
pred <- h2o.predict(fit, test.hex)

performace <- h2o.performance(fit, test.hex)
# test auc
test_auc <- performace@metrics$AUC

cm <- h2o.confusionMatrix(fit, newdata = test.hex)
cm

accuracy <- (cm[1,1] + cm[2,2]) / (cm$bad[3] + cm$good[3])
accuracy


precision <-  cm[2,2] / cm$good[3]
precision

recall <- cm[2,2]/ (cm[2,1] + cm[2,2]) 
recall

f1 <- 2*(precision*recall)/(precision+recall)
f1

Metric <- c(c("accuracy", "precision", "recall", "F1") |> str_to_title(), "ROC-AUC")
Results <- c(accuracy, precision, recall, f1, test_auc) |> round(digits = 3)

data.frame(Metric, Results)


## -----------------------------------------------------------------------------------------------
training$class <- ifelse(training$credit_class == "good", 1, 0)
test$class <- ifelse(test$credit_class == "good", 1, 0)

# convert to DMartix
dtrain <- xgb.DMatrix(as.matrix(training[,-1]), label = training$class)
dtest <- xgb.DMatrix(as.matrix(test[,-1]), label = test$class)

predictors_names <- colnames(test[-1])


## -----------------------------------------------------------------------------------------------
params <- list(
  objective = "binary:logistic",
  max_depth = c(3,5),
  eta = 0.0001,
  nthread = 8,
  eval_metric = "logloss",
  alpha = 1,
  lambda = 0)

cv_results <-  xgb.cv(
  params = params,
  data = dtrain,
  nrounds = 30000,  # Number of boosting rounds / iterations
  nfold = 5,    # Number of folds
  stratified = TRUE,
  early_stopping_rounds = 10,
  verbose = TRUE
)

optimal_rounds <- which.min(cv_results$evaluation_log$test_logloss_mean)
optimal_rounds


## -----------------------------------------------------------------------------------------------
final_xgboost <- xgboost(params = params,data = dtrain, nrounds = optimal_rounds, early_stopping_rounds = 10)



## -----------------------------------------------------------------------------------------------
# xgb.save(final_xgboost, "./model/xgboost")
# xgb.load("./model/xgboost")


## -----------------------------------------------------------------------------------------------
# prediction
pred_xgboost <- predict(final_xgboost, newdata = dtest, type = "response")
pred_xgboost

data.frame(pred = pred_xgboost, actual = test$class)

roc_df <- pROC::roc(test$class, pred_xgboost)
auc(roc_df)




## -----------------------------------------------------------------------------------------------
pred_class <- ifelse(pred_xgboost > .5, 1,0)
caret::confusionMatrix(table(Actual = test$class, Prediction = pred_class), positive = "1")

