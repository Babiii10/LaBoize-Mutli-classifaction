# Multi-Class Classification Implementation

## Overview
This document describes the multi-class classification implementation added to the LaBoize Omics Analysis application. The application now supports both **binary** and **multi-class** classification with automatic detection.

## Key Changes

### 1. **Statistical Tests** (`global.R` - `diffexptest` function)

#### Binary Classification (2 classes)
- Wilcoxon test (non-parametric)
- Student's t-test (parametric)
- Original functionality preserved

#### Multi-Class Classification (3+ classes)
- **Kruskal-Wallis test** (non-parametric) - automatically used when `test="Wtest"` and n_classes > 2
- **ANOVA** (parametric) - automatically used when `test="Ttest"` and n_classes > 2
- Returns p-values testing if at least one class differs
- Calculates mean for each class
- Computes multi-class AUC using `pROC::multiclass.roc()`

**Output for multi-class:**
- `pval[Kruskal|ANOVA]` - p-value from omnibus test
- `BHadjustpval[Kruskal|ANOVA]` - Benjamini-Hochberg adjusted p-value
- `AUC_multiclass` - One-vs-Rest average AUC
- `mean_[class_name]` - Mean value for each class

---

### 2. **Multivariate Variable Selection** (`global.R` - `multivariateselection` function)

#### Binary Classification
- Uses `glmnet(..., family="binomial")`
- Original functionality preserved

#### Multi-Class Classification
- Uses `glmnet(..., family="multinomial")`
- Encoding: classes encoded as 0, 1, 2, ...
- Returns list of coefficient matrices (one per class)
- Aggregates coefficients using max absolute value across classes
- Calculates multi-class AUC for selected variables

**Output for multi-class:**
- `coefficient_max` - Maximum absolute coefficient across all classes
- `AUC_multiclass` - One-vs-Rest AUC
- `mean_[class_name]` - Mean for each class
- `coef_list` - Full list of coefficients per class

---

### 3. **ROC Curves** (`global.R` - `ROCcurve` function)

#### Binary Classification
- Single ROC curve
- AUC displayed on plot

#### Multi-Class Classification
- **One-vs-Rest ROC curves** - one curve per class
- Each curve treats one class as positive, all others as negative
- Requires probability matrix (n_samples × n_classes)
- Displays mean AUC across all classes

**Plot features:**
- Multiple colored curves (one per class)
- Legend showing class names
- Mean AUC annotation
- Diagonal reference line

---

### 4. **Helper Functions** (`global.R`)

New utility functions for multi-class support:

```r
is_multiclass(group_factor)
# Returns TRUE if more than 2 classes

get_n_classes(group_factor)
# Returns number of classes

process_multiclass_scores(scores, group_factor, model_votes=NULL)
# Converts scores: vector for binary, matrix for multi-class

predict_from_scores(scores, group_factor, threshold=0.5)
# Binary: uses threshold
# Multi-class: uses argmax of probabilities

calculate_classification_metrics(true_labels, predicted_labels)
# Binary: sensitivity, specificity, accuracy
# Multi-class: per-class metrics, macro-averaged metrics
```

---

### 5. **User Interface** (`ui.R`)

#### Removed
- **"inverse" checkbox** - not applicable for multi-class

#### Modified
- Class summary now displays all classes dynamically
- Color-coded display: `textOutput("class_summary")`

#### Preserved
- All other UI elements remain functional
- Compatible with both binary and multi-class workflows

---

## Model Compatibility

### ✅ Already Multi-Class Compatible
These models natively support multi-class classification:

1. **Random Forest** (`randomForest`)
   - Returns `votes` matrix (n_samples × n_classes)
   - Use `model$votes` for probabilities

2. **SVM** (`e1071::svm`)
   - Set `probability=TRUE`
   - Returns probability matrix via `predict(..., probability=TRUE)`

3. **Naive Bayes** (`e1071::naiveBayes`)
   - Returns probabilities via `predict(..., type="raw")`

4. **K-Nearest Neighbors** (`class::knn`)
   - Returns class labels directly
   - Can calculate probabilities from k neighbors

### 🔄 Requires Configuration
These models need parameter changes for multi-class:

1. **XGBoost**
   ```r
   params <- list(
     objective = "multi:softprob",  # Changed from "binary:logistic"
     num_class = n_classes,
     eval_metric = "mlogloss"
   )
   ```

2. **ElasticNet/Lasso/Ridge** (glmnet)
   ```r
   glmnet(x, y, family="multinomial")  # Changed from "binomial"
   ```

---

## Classification Workflow

### Binary Classification (2 classes)
```
Data → Statistical Test (Wilcoxon/Student)
    → Variable Selection (Lasso/ElasticNet with family="binomial")
    → Model Training (threshold-based prediction)
    → ROC Curve (single curve)
    → Confusion Matrix (2×2)
```

### Multi-Class Classification (3+ classes)
```
Data → Statistical Test (Kruskal-Wallis/ANOVA)
    → Variable Selection (Lasso/ElasticNet with family="multinomial")
    → Model Training (argmax prediction)
    → ROC Curves (One-vs-Rest, one curve per class)
    → Confusion Matrix (N×N)
```

---

## Metrics Interpretation

### Binary Classification
- **Sensitivity** = TP / (TP + FN)
- **Specificity** = TN / (TN + FP)
- **AUC** = Area under single ROC curve

### Multi-Class Classification
- **Sensitivity (per class)** = TP / (TP + FN) for that class
- **Precision (per class)** = TP / (TP + FP) for that class
- **Macro-averaged Sensitivity** = Mean of all class sensitivities
- **Macro-averaged Precision** = Mean of all class precisions
- **AUC (multi-class)** = Mean of One-vs-Rest AUCs

---

## Example Usage

### Loading Data
```r
# Your data should have:
# - First column: class labels (factor with 2+ levels)
# - Other columns: features/variables

# Example with 3 classes:
data <- data.frame(
  class = factor(c("A", "B", "C", "A", "B", "C", ...)),
  var1 = c(...),
  var2 = c(...),
  ...
)
```

### Statistical Testing
```r
# Automatic detection: Wilcoxon for binary, Kruskal-Wallis for multi-class
results <- diffexptest(data, test="Wtest")

# Results columns for multi-class:
# - name
# - pvalKruskal (or pvalANOVA)
# - BHadjustpvalKruskal
# - AUC_multiclass
# - mean_A, mean_B, mean_C
```

### Variable Selection
```r
# Automatic detection: binomial for binary, multinomial for multi-class
selection <- multivariateselection(data, method="lasso")

# For multi-class, returns:
# - selected_vars
# - coefficient_max (aggregated across classes)
# - coef_list (detailed per class)
```

### ROC Curves
```r
# Binary: decisionvalues = vector of scores
ROCcurve(validation, decisionvalues)

# Multi-class: decisionvalues = matrix (n_samples × n_classes)
ROCcurve(validation, probability_matrix)
```

---

## Testing Recommendations

1. **Test with 2 classes** - Ensure backward compatibility
2. **Test with 3 classes** - Basic multi-class functionality
3. **Test with 5+ classes** - Scalability
4. **Test with imbalanced classes** - Real-world scenario

---

## Future Enhancements

### Potential Improvements
1. **Post-hoc tests** - Dunn's test, Tukey HSD for pairwise comparisons
2. **Fold Change for multi-class** - Define reference class (e.g., mean of all classes)
3. **Threshold optimization for multi-class** - Optimize per-class thresholds
4. **Visualization enhancements**
   - Heatmap of confusion matrix
   - Per-class feature importance plots
   - Class probability distributions

### Model Enhancements
1. **LightGBM** - Add `objective="multiclass"` support
2. **Deep Learning** - Add neural network models via Keras/TensorFlow
3. **Ensemble Methods** - Stacking, voting classifiers

---

## References

- **glmnet**: Friedman, J., Hastie, T., & Tibshirani, R. (2010). Regularization Paths for Generalized Linear Models via Coordinate Descent. *Journal of Statistical Software*, 33(1), 1-22.
- **pROC**: Robin, X., Turck, N., Hainard, A., et al. (2011). pROC: an open-source package for R and S+ to analyze and compare ROC curves. *BMC Bioinformatics*, 12, 77.
- **Multi-class ROC**: Hand, D. J., & Till, R. J. (2001). A Simple Generalisation of the Area Under the ROC Curve for Multiple Class Classification Problems. *Machine Learning*, 45(2), 171-186.

---

## Contact & Support

For questions or issues related to multi-class classification:
1. Check this documentation
2. Review function comments in `global.R`
3. Test with example datasets in `examples/` directory

---

## Version History

- **v2.0** (2025-12-20) - Multi-class classification implementation
  - Added support for 3+ classes
  - Automatic detection of binary vs multi-class
  - Backward compatible with binary classification
  - New helper functions for multi-class handling
