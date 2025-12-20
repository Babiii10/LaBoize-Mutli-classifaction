# Simplification : Application Multi-classe Uniquement

## 🎯 Objectif

Simplifier l'application pour qu'elle ne gère **QUE la classification multi-classe**, même pour 2 classes.
Supprimer toutes les branches binaires `if(n_classes == 2)` et utiliser uniquement la logique multi-classe.

---

## ✅ Changements Déjà Effectués

### 1. **Fonctions Helper** (global.R lignes 48-95)
- ✅ Supprimé : `is_multiclass()`
- ✅ Supprimé : `process_multiclass_scores()`
- ✅ Simplifié : `predict_from_scores()` - **uniquement argmax** (pas de threshold)
- ✅ Simplifié : `calculate_classification_metrics()` - **uniquement métriques multi-classe**

### 2. **diffexptest()** (global.R lignes 757-835)
- ✅ Supprimé toute la branche binaire (Wilcoxon/Student)
- ✅ Utilise **uniquement Kruskal-Wallis/ANOVA**
- ✅ Fonctionne pour 2+ classes
- ✅ Retourne toujours : `AUC_multiclass`, `mean_[class_name]` pour chaque classe

---

## ⚠️ Changements Restants à Effectuer

### 3. **multivariateselection()** (global.R lignes 850+)
**À FAIRE** : Supprimer la branche binaire (`if(n_classes == 2)`) et garder uniquement multinomial

```r
# SUPPRIMER cette section binaire :
if(n_classes == 2){
  group <- ifelse(toto[,1] == lev[1], 1, 0)
  cvfit <- cv.glmnet(x, group, family="binomial", ...)
  fit <- glmnet(x, group, family="binomial", ...)
  ...
}

# GARDER uniquement :
y <- toto[,1]  # Factor
cvfit <- cv.glmnet(x, y, family="multinomial", ...)
fit <- glmnet(x, y, family="multinomial", ...)
```

**Code corrigé** : Voir `MULTI_CLASS_ONLY_MIGRATION.R` lignes 115-195

---

### 4. **ROCcurve()** (global.R lignes 2884+)
**À FAIRE** : Supprimer la branche binaire et garder uniquement One-vs-Rest

```r
# SUPPRIMER :
if(n_classes == 2){
  data <- roc(validation, decisionvalues)
  # Plot single ROC curve
  ...
}

# GARDER uniquement :
# One-vs-Rest ROC curves (fonctionne pour 2+ classes)
for(i in 1:n_classes){
  binary_response <- ifelse(...)
  roc_obj <- roc(binary_response, decisionvalues[, i])
  ...
}
```

**Code corrigé** : Voir `MULTI_CLASS_ONLY_MIGRATION.R` lignes 197-330

---

### 5. **Tous les Modèles dans modelfunction()** (global.R lignes 1600+)

Chaque modèle a une section `if(n_classes == 2) {...} else {...}` à **supprimer**.

#### **Random Forest** (lignes ~2048)
```r
# SUPPRIMER :
if(n_classes == 2){
  scorelearning = data.frame(model$votes[,lev["positif"]])
  predictclasslearning[which(scorelearning >= threshold)] <- lev["positif"]
  ...
}

# GARDER uniquement :
scorelearning <- model$votes  # Matrix (n_samples × n_classes)
predictclasslearning <- predict_from_scores(scorelearning, learningmodel[,1])
```

#### **SVM** (lignes ~2121)
```r
# SUPPRIMER branche binaire avec decision.values
# GARDER uniquement :
pred_probs <- attr(predict(model, ..., probability=TRUE), "probabilities")
scorelearning <- pred_probs[, lev]
predictclasslearning <- predict_from_scores(scorelearning, learningmodel[,1])
```

#### **LightGBM** (lignes ~2150)
```r
# SUPPRIMER branche binaire
# GARDER uniquement :
y <- as.numeric(learningmodel[,1]) - 1
params <- list(objective="multiclass", num_class=n_classes, ...)
predictions <- matrix(predict(model, x), ncol=n_classes, byrow=TRUE)
predictclasslearning <- predict_from_scores(predictions, learningmodel[,1])
```

#### **Naive Bayes** (lignes ~2330)
```r
# SUPPRIMER extraction d'une seule colonne
# GARDER uniquement :
pred_probs <- predict(model, ..., type="raw")
scorelearning <- pred_probs[, lev]
predictclasslearning <- predict_from_scores(scorelearning, learningmodel[,1])
```

#### **KNN** (lignes ~2469)
```r
# SUPPRIMER calcul d'un seul vecteur de probabilités
# GARDER uniquement :
scorelearning_matrix <- matrix(0, nrow=..., ncol=n_classes)
for(i in 1:nrow(...)){
  for(j in 1:n_classes){
    scorelearning_matrix[i,j] <- sum(k_nearest_labels == lev[j]) / k
  }
}
predictclasslearning <- predict_from_scores(scorelearning_matrix, learningmodel[,1])
```

#### **ElasticNet** (lignes ~2531)
```r
# SUPPRIMER toutes les branches binaires
# GARDER uniquement :
y <- learningmodel[,1]  # Factor
cvfit <- cv.glmnet(x, y, family="multinomial", type.measure="class", ...)
predictions <- predict(..., type="response")
if(length(dim(predictions)) == 3) predictions <- predictions[,,1]
predictclasslearning <- predict_from_scores(predictions, learningmodel[,1])
```

#### **XGBoost** (lignes ~2675)
```r
# SUPPRIMER branche binaire
# GARDER uniquement :
y <- as.numeric(learningmodel[,1]) - 1
params <- list(objective="multi:softprob", num_class=n_classes, ...)
predictions <- matrix(predict(model, x), ncol=n_classes, byrow=TRUE)
predictclasslearning <- predict_from_scores(predictions, learningmodel[,1])
```

---

### 6. **Validation Predictions** (global.R lignes ~2800+)

**CRITIQUE** : Toutes les prédictions sur le jeu de validation doivent être modifiées

Actuellement (BINAIRE) :
```r
if(modelparameters$modeltype == "randomforest"){
  scoreval <- predict(...)[,lev["positif"]]  # ❌ Vecteur
  predictclassval[which(scoreval >= threshold)] <- lev["positif"]  # ❌ Threshold
  ...
}
```

À REMPLACER par (MULTI-CLASSE) :
```r
if(modelparameters$modeltype == "randomforest"){
  scoreval <- predict(..., type="prob")  # ✅ Matrice
  predictclassval <- predict_from_scores(scoreval, validation[,1])  # ✅ Argmax
}
```

**Code corrigé pour TOUS les modèles** : Voir `MULTI_CLASS_ONLY_MIGRATION.R` lignes 450-580

---

## 📝 Résumé des Actions

### ✅ Déjà Fait (3/9)
1. ✅ Helper functions simplifiées
2. ✅ diffexptest() simplifié
3. ✅ Documentation créée (ce fichier + MULTI_CLASS_ONLY_MIGRATION.R)

### ⚠️ À Faire (6/9)
4. ⚠️ multivariateselection() - Supprimer branche binaire
5. ⚠️ ROCcurve() - Supprimer branche binaire
6. ⚠️ Random Forest - Supprimer branche binaire
7. ⚠️ Tous les autres modèles - Supprimer branches binaires (SVM, LightGBM, NB, KNN, ElasticNet, XGBoost)
8. ⚠️ Validation predictions - Modifier TOUS les modèles
9. ⚠️ Tests finaux - Vérifier que tout fonctionne pour 2, 3, 4+ classes

---

## 🚀 Comment Appliquer les Changements

### Option 1 : Manuel
1. Ouvrir `global.R`
2. Pour chaque fonction/modèle, chercher `if(n_classes == 2)`
3. Supprimer la branche binaire
4. Garder uniquement la branche multi-classe (et enlever le `else`)

### Option 2 : Utiliser le Code Pré-fait
1. Ouvrir `MULTI_CLASS_ONLY_MIGRATION.R`
2. Copier-coller les fonctions simplifiées dans `global.R`
3. Remplacer les fonctions existantes

---

## ⚙️ Test de Validation

Après avoir appliqué tous les changements, tester avec :

1. **Dataset à 2 classes** (ex: sous-ensemble d'Iris avec 2 espèces)
   - ✅ Doit fonctionner avec Kruskal-Wallis/ANOVA
   - ✅ Doit retourner matrice de probabilités (2 colonnes)
   - ✅ Doit utiliser argmax pour prédire

2. **Dataset à 3 classes** (ex: Iris complet)
   - ✅ Doit fonctionner avec tous les modèles
   - ✅ Doit retourner matrice de probabilités (3 colonnes)
   - ✅ ROC One-vs-Rest avec 3 courbes

3. **Dataset à 4+ classes**
   - ✅ Doit fonctionner sans erreur
   - ✅ Confusion matrix N×N correcte

---

## 📊 Avantages de la Simplification

### Avant (Binaire + Multi-classe)
- ❌ Code dupliqué (2 chemins pour chaque fonction)
- ❌ Risque d'inconsistance entre binaire et multi-classe
- ❌ Plus difficile à maintenir
- ❌ ~1700 lignes de code pour gérer les 2 cas

### Après (Multi-classe Uniquement)
- ✅ Code simplifié (1 seul chemin)
- ✅ Logique unifiée
- ✅ Plus facile à maintenir
- ✅ ~800-900 lignes de code (réduction de ~50%)
- ✅ Fonctionne pour 2, 3, 4, 5+ classes

---

## 🎯 Prochaines Étapes

1. Appliquer les changements restants (voir sections 4-8 ci-dessus)
2. Tester avec datasets réels
3. Commit final
4. Mettre à jour la documentation utilisateur

---

## 📞 Support

Si besoin d'aide pour appliquer les changements :
- Consulter `MULTI_CLASS_ONLY_MIGRATION.R` pour le code complet
- Chaque section est documentée avec avant/après
- Templates génériques fournis pour tous les modèles
