# =============================================================================
# MIGRATION VERS MULTI-CLASSE UNIQUEMENT
# =============================================================================
# Ce fichier contient toutes les fonctions simplifiées pour ne gérer QUE
# du multi-classe (même pour 2 classes)
#
# À FAIRE : Remplacer les fonctions dans global.R par ces versions
# =============================================================================

# =============================================================================
# 1. HELPER FUNCTIONS (déjà fait dans global.R lignes 48-95)
# =============================================================================
# ✅ get_n_classes() - OK
# ✅ predict_from_scores() - OK
# ✅ calculate_classification_metrics() - OK

# =============================================================================
# 2. DIFF EXP TEST - Multi-classe uniquement
# =============================================================================

diffexptest <- function(toto, test="Kruskal"){
  # Test statistical pour multi-classe (fonctionne aussi pour 2 classes)
  # test = "Kruskal" : Kruskal-Wallis (non-paramétrique)
  # test = "ANOVA" : ANOVA (paramétrique)

  group <- toto[,1]
  toto <- toto[,-1]
  n_classes <- length(levels(group))

  pval <- vector()
  adjustpval <- vector()

  # Calculate mean for each class
  means_by_class <- matrix(nrow = ncol(toto), ncol = n_classes)
  colnames_means <- paste("mean", levels(group), sep = "_")

  # Calculate overall mean
  mean_overall <- vector()

  # Multi-class AUC
  auc_multiclass <- vector()

  for (i in 1:max(1,ncol(toto))){
    # Statistical test
    if(test == "Kruskal"){
      # Kruskal-Wallis test (non-parametric)
      pval[i] <- tryCatch({
        kruskal.test(toto[,i] ~ group)$p.value
      }, error = function(e) return(1))
    } else if(test == "ANOVA"){
      # ANOVA (parametric)
      pval[i] <- tryCatch({
        summary(aov(toto[,i] ~ group))[[1]][1,"Pr(>F)"]
      }, error = function(e) return(1))
    }

    # Calculate means for each class
    for(j in 1:n_classes){
      class_data <- toto[which(group == levels(group)[j]), i]
      means_by_class[i, j] <- mean(class_data, na.rm = TRUE) + 0.0001
    }

    # Overall mean
    mean_overall[i] <- mean(toto[,i], na.rm = TRUE) + 0.0001

    # Multi-class AUC (one-vs-rest average)
    auc_multiclass[i] <- tryCatch({
      roc_obj <- multiclass.roc(group, toto[,i], quiet=TRUE)
      as.numeric(auc(roc_obj))
    }, error = function(e) return(0.5))
  }

  pval[which(is.na(pval))] <- 1
  adjustpval <- p.adjust(pval, method = "BH")

  # Build result dataframe
  listgen <- data.frame(
    name = colnames(toto),
    pval = pval,
    adjustpval = adjustpval,
    auc = auc_multiclass,
    mean_overall = mean_overall
  )

  # Add means for each class
  for(j in 1:n_classes){
    listgen[, paste("mean", levels(group)[j], sep = "_")] <- means_by_class[, j]
  }

  # Rename columns
  colnames(listgen)[2] <- paste("pval", test, sep = "")
  colnames(listgen)[3] <- paste("BHadjustpval", test, sep = "")
  colnames(listgen)[4] <- "AUC_multiclass"

  return(listgen)
}

# =============================================================================
# 3. MULTIVARIATE SELECTION - Multi-classe uniquement
# =============================================================================

multivariateselection <- function(toto, method="lasso", lambda=NULL, alpha=0.5, nlambda=100){
  # Multivariate variable selection using multinomial glmnet
  # Works for 2+ classes

  lev <- levels(toto[,1])
  n_classes <- length(lev)
  x <- as.matrix(toto[,-1])

  # Set alpha based on method
  if(method == "lasso"){
    alpha <- 1
  } else if(method == "ridge" | method == "cox"){
    alpha <- 0
  }

  # Use factor for multinomial (works for 2+ classes)
  y <- toto[,1]

  # Perform cross-validation to find optimal lambda if not provided
  if(is.null(lambda)){
    set.seed(20011203)
    cvfit <- cv.glmnet(x, y, family="multinomial",
                       alpha=alpha, nlambda=nlambda,
                       type.measure="class", nfolds=min(5, nrow(toto)-1),
                       type.multinomial = "grouped")
    lambda <- cvfit$lambda.min
    lambda_1se <- cvfit$lambda.1se
  } else {
    cvfit <- NULL
    lambda_1se <- lambda
  }

  # Fit model with optimal lambda
  fit <- glmnet(x, y, family="multinomial", alpha=alpha, lambda=lambda,
                type.multinomial = "grouped")

  # Extract coefficients (list of matrices, one per class)
  coef_list <- coef(fit, s=lambda)

  # Aggregate coefficients across classes (use max absolute value)
  coef_aggregated <- rep(0, ncol(x))
  names(coef_aggregated) <- colnames(x)

  for(class_idx in 1:n_classes){
    coef_matrix <- as.matrix(coef_list[[class_idx]])
    coef_values_class <- coef_matrix[-1, 1]  # Remove intercept
    # Keep maximum absolute coefficient across classes
    coef_aggregated <- pmax(abs(coef_aggregated), abs(coef_values_class))
  }

  # Select non-zero coefficients
  selected_vars <- names(coef_aggregated[coef_aggregated > 1e-10])

  # Calculate additional statistics for selected variables
  if(length(selected_vars) > 0){
    # Multi-class AUC for each selected variable
    auc_values <- sapply(selected_vars, function(var){
      tryCatch({
        roc_obj <- multiclass.roc(toto[,1], x[, var], quiet=TRUE)
        as.numeric(auc(roc_obj))
      }, error = function(e) return(0.5))
    })

    # Mean values by group for each class
    means_matrix <- matrix(nrow=length(selected_vars), ncol=n_classes)
    for(j in 1:n_classes){
      means_matrix[, j] <- colMeans(x[which(toto[,1] == lev[j]), selected_vars, drop=FALSE], na.rm=TRUE)
    }
    colnames(means_matrix) <- paste("mean", lev, sep="_")

    # Create results dataframe
    results <- data.frame(
      name = selected_vars,
      coefficient_max = coef_aggregated[selected_vars],
      AUC_multiclass = auc_values,
      stringsAsFactors = FALSE
    )

    # Add means for each class
    results <- cbind(results, means_matrix)

    # Sort by absolute coefficient value
    results <- results[order(abs(results$coefficient_max), decreasing=TRUE), ]
  } else {
    results <- data.frame()
  }

  # Return results with model information
  return(list(
    results = results,
    selected_vars = selected_vars,
    all_coefficients = coef_aggregated,
    coef_list = coef_list,
    lambda = lambda,
    lambda_1se = lambda_1se,
    alpha = alpha,
    cvfit = cvfit,
    fit = fit,
    method = method,
    n_classes = n_classes
  ))
}

# =============================================================================
# 4. ROC CURVE - Multi-classe uniquement
# =============================================================================

ROCcurve <- function(validation, decisionvalues, maintitle="Roc curve", graph=T, ggplot=T){
  # ROC curve for multi-class (works for 2+ classes)
  # decisionvalues must be a matrix (n_samples × n_classes)

  validation <- factor(validation, levels = rev(levels(validation)), ordered = TRUE)
  n_classes <- length(levels(validation))

  # Check if decisionvalues is a matrix
  if(!is.matrix(decisionvalues)){
    if(!graph){
      return(data.frame(message="Multi-class ROC requires probability matrix"))
    }
    if(ggplot){
      p <- ggplot() +
        annotate("text", x=0.5, y=0.5, label="Multi-class ROC requires\nprobability matrix for each class", size=6) +
        labs(title = maintitle) +
        theme_minimal()
      return(p)
    }
  }

  # Calculate One-vs-Rest ROC curves for each class
  roc_list <- list()
  auc_values <- vector()
  class_names <- levels(validation)

  for(i in 1:n_classes){
    # Create binary indicator for this class
    binary_response <- ifelse(as.numeric(validation) == (n_classes - i + 1), 1, 0)

    # Get probabilities for this class
    class_probs <- decisionvalues[, i]

    # Calculate ROC
    roc_obj <- tryCatch({
      roc(binary_response, class_probs, quiet=TRUE)
    }, error = function(e){
      return(NULL)
    })

    if(!is.null(roc_obj)){
      roc_list[[class_names[n_classes - i + 1]]] <- roc_obj
      auc_values[i] <- as.numeric(auc(roc_obj))
    }
  }

  # Calculate mean AUC
  mean_auc <- mean(auc_values, na.rm=TRUE)

  if(!graph){
    return(data.frame(
      class = names(roc_list),
      auc = auc_values
    ))
  }

  if(ggplot){
    # Plot One-vs-Rest ROC curves
    col <- gg_color_hue(n_classes + 1)
    bin = 0.01
    diag = data.frame(x = seq(0, 1, by = bin), y = rev(seq(0, 1, by = bin)))

    # Create plot
    p <- ggplot() +
      geom_line(data = diag, aes(x = x, y = y), color = col[n_classes + 1], linetype="dashed")

    # Add ROC curve for each class
    for(i in 1:length(roc_list)){
      class_name <- names(roc_list)[i]
      roc_obj <- roc_list[[class_name]]

      y <- rev(roc_obj$sensitivities)
      x <- rev(roc_obj$specificities)
      roc_df <- data.frame(x=x, y=y, class=class_name)

      p <- p +
        geom_line(data = roc_df, aes(x = x, y = y, color = class), size=1)
    }

    # Add AUC annotations
    auc_text <- paste0(names(roc_list), ": ", round(auc_values, 3), collapse="\n")
    mean_auc_text <- paste0("Mean AUC: ", round(mean_auc, 3))

    f <- p +
      theme(axis.text = element_text(size = 16),
            title = element_text(size = 15),
            axis.text.x = element_text(size = 12, face = 'bold'),
            axis.text.y = element_text(size = 12, face = 'bold'),
            axis.title.x = element_text(size = 15, face = 'bold'),
            axis.title.y = element_text(size = 15, face = 'bold'),
            legend.position = "right") +
      labs(y = "Sensitivity (TPR)", x = "1 - Specificity (FPR)",
           title = maintitle, color = "Class") +
      annotate("text", x=0.3, y=0.1, label=mean_auc_text, size=5, fontface="bold") +
      scale_x_reverse()

    f
  }
}

# =============================================================================
# 5. MODEL FUNCTIONS - Versions simplifiées multi-classe uniquement
# =============================================================================
# Note : Les modèles dans modelfunction() doivent être modifiés pour
# supprimer toutes les branches if(n_classes == 2)

# Template général pour tous les modèles :
#
# 1. Encodage des labels :
#    - XGBoost/LightGBM : y <- as.numeric(learningmodel[,1]) - 1
#    - ElasticNet : y <- learningmodel[,1] (factor)
#    - SVM/RF/NB/KNN : utilisent directement le factor
#
# 2. Paramètres :
#    - XGBoost : objective="multi:softprob", num_class=n_classes
#    - LightGBM : objective="multiclass", num_class=n_classes
#    - ElasticNet : family="multinomial"
#    - SVM : probability=TRUE (déjà OK)
#    - RF/NB/KNN : natifs multi-classe
#
# 3. Prédictions :
#    - Toujours retourner une matrice (n_samples × n_classes)
#    - Utiliser predict_from_scores(scorelearning, learningmodel[,1])
#    - Pas de threshold, uniquement argmax

# =============================================================================
# EXEMPLE : Random Forest simplifié
# =============================================================================

model_randomforest_multiclass_only <- function(){
  # Code simplifié pour Random Forest
  # À remplacer dans la section Random Forest de modelfunction()

  # Training
  learningmodel <- as.data.frame(learningmodel[sort(rownames(learningmodel)),])
  x <- as.data.frame(learningmodel[,-1])
  colnames(x) <- colnames(learningmodel)[-1]
  x <- as.data.frame(x[,sort(colnames(x))])

  set.seed(20011203)
  ntree_param <- ifelse(is.null(modelparameters$ntree), 1000, modelparameters$ntree)

  # ... hyperparameter tuning code ...

  model <- randomForest(x=x, y=learningmodel[,1],
                       ntree=ntree_param,
                       mtry=optimal_mtry,
                       nodesize=nodesize_param,
                       importance=T)

  # Predictions - ALWAYS use probability matrix
  scorelearning <- model$votes  # Matrix (n_samples × n_classes)

  # Predict using argmax (no threshold)
  predictclasslearning <- predict_from_scores(scorelearning, learningmodel[,1])
}

# =============================================================================
# EXEMPLE : XGBoost simplifié
# =============================================================================

model_xgboost_multiclass_only <- function(){
  # Code simplifié pour XGBoost
  # À remplacer dans la section XGBoost de modelfunction()

  x <- as.matrix(learningmodel[,-1])
  n_classes <- get_n_classes(learningmodel[,1])

  # Encode y as 0, 1, 2, ...
  y <- as.numeric(learningmodel[,1]) - 1

  # Create DMatrix
  dtrain <- xgb.DMatrix(data = x, label = y)

  # Parameters - ALWAYS multinomial
  params <- list(
    objective = "multi:softprob",
    num_class = n_classes,
    eval_metric = "mlogloss",
    max_depth = max_depth_param,
    eta = eta_param,
    ...
  )

  # Train
  model <- xgb.train(
    params = params,
    data = dtrain,
    nrounds = nrounds_param,
    verbose = 0
  )

  # Predictions - ALWAYS matrix
  predictions_raw <- xgboost:::predict.xgb.Booster(model, x)
  scorelearning <- matrix(predictions_raw, ncol=n_classes, byrow=TRUE)
  colnames(scorelearning) <- lev

  # Predict using argmax
  predictclasslearning <- predict_from_scores(scorelearning, learningmodel[,1])
}

# =============================================================================
# EXEMPLE : ElasticNet simplifié
# =============================================================================

model_elasticnet_multiclass_only <- function(){
  # Code simplifié pour ElasticNet
  # À remplacer dans la section ElasticNet de modelfunction()

  x <- as.matrix(learningmodel[,-1])
  y <- learningmodel[,1]  # Factor for multinomial
  n_classes <- get_n_classes(y)

  # Cross-validation - ALWAYS multinomial
  set.seed(20011203)
  cvfit <- cv.glmnet(x, y, family="multinomial",
                     alpha=alpha_param,
                     type.measure="class",
                     nfolds=min(10, nrow(learningmodel)-1))

  lambda_param <- cvfit$lambda.min
  model <- list(glmnet_model=cvfit, lambda=lambda_param, alpha=alpha_param)

  # Predictions - ALWAYS 3D array → matrix
  predictions_raw <- glmnet:::predict.cv.glmnet(model$glmnet_model,
                                               newx=x, s=lambda_param,
                                               type="response")

  # Extract matrix from 3D array
  if(length(dim(predictions_raw)) == 3){
    scorelearning <- predictions_raw[,,1]
  } else {
    scorelearning <- predictions_raw
  }
  colnames(scorelearning) <- lev

  # Predict using argmax
  predictclasslearning <- predict_from_scores(scorelearning, learningmodel[,1])
}

# =============================================================================
# 6. VALIDATION PREDICTIONS - Multi-classe uniquement
# =============================================================================
# Toutes les prédictions sur le jeu de validation doivent suivre le même pattern

validation_predictions_template <- function(){
  # Template pour TOUTES les prédictions de validation
  # À appliquer à : RF, SVM, XGBoost, LightGBM, ElasticNet, Naive Bayes, KNN

  # 1. Préparer les données de validation
  validationmodel <- ...  # preprocessing

  # 2. Obtenir les probabilités (TOUJOURS une matrice)
  if(modelparameters$modeltype == "randomforest"){
    scoreval <- randomForest:::predict.randomForest(object=model, type="prob",
                                                    newdata=validationmodel)
    # scoreval est déjà une matrice (n_samples × n_classes)
  }

  if(modelparameters$modeltype == "svm"){
    pred_probs <- attr(predict(model, newdata=validationmodel, probability=TRUE),
                      "probabilities")
    scoreval <- pred_probs[, lev]  # Reorder columns
  }

  if(modelparameters$modeltype == "xgboost"){
    x_val <- as.matrix(validationmodel)
    dval <- xgb.DMatrix(data = x_val)
    predictions_raw <- xgboost:::predict.xgb.Booster(model, dval)
    scoreval <- matrix(predictions_raw, ncol=n_classes, byrow=TRUE)
    colnames(scoreval) <- lev
  }

  if(modelparameters$modeltype == "lightgbm"){
    x_val <- as.matrix(validationmodel)
    predictions_raw <- predict(model, x_val)
    scoreval <- matrix(predictions_raw, ncol=n_classes, byrow=TRUE)
    colnames(scoreval) <- lev
  }

  if(modelparameters$modeltype == "elasticnet"){
    x_val <- as.matrix(validationmodel)
    if(inherits(model$glmnet_model, "cv.glmnet")){
      predictions_raw <- glmnet:::predict.cv.glmnet(model$glmnet_model,
                                                   newx=x_val, s=model$lambda,
                                                   type="response")
    } else {
      predictions_raw <- glmnet::predict.glmnet(model$glmnet_model,
                                               newx=x_val, s=model$lambda,
                                               type="response")
    }

    if(length(dim(predictions_raw)) == 3){
      scoreval <- predictions_raw[,,1]
    } else {
      scoreval <- predictions_raw
    }
    colnames(scoreval) <- lev
  }

  if(modelparameters$modeltype == "naivebayes"){
    pred_probs <- e1071:::predict.naiveBayes(model, validationmodel, type="raw")
    scoreval <- pred_probs[, lev]
  }

  if(modelparameters$modeltype == "knn"){
    # KNN requires manual probability calculation for validation set too
    scoreval_matrix <- matrix(0, nrow=nrow(validationmodel), ncol=n_classes)
    colnames(scoreval_matrix) <- lev

    for(i in 1:nrow(validationmodel)){
      # Get k nearest neighbors from training set
      distances <- apply(model$train_data, 1, function(row) {
        sqrt(sum((as.numeric(validationmodel[i,]) - as.numeric(row))^2))
      })

      k_nearest_idx <- order(distances)[1:model$optimal_k]
      k_nearest_labels <- model$train_labels[k_nearest_idx]

      # Calculate probability for each class
      for(j in 1:n_classes){
        scoreval_matrix[i, j] <- sum(k_nearest_labels == lev[j]) / model$optimal_k
      }
    }
    scoreval <- scoreval_matrix
  }

  # 3. Predict using argmax (PAS de threshold!)
  predictclassval <- predict_from_scores(scoreval, validation[,1])
}

# =============================================================================
# FIN DU FICHIER DE MIGRATION
# =============================================================================
