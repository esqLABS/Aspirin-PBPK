################################
# Authors:     Andre Dallmann, Nina Nauwelaerts, Sophie Fischer-Holzhausen
# Property:     ESQlabs GmbH
# Initial Date: 11.02.2026
# Last updated: 11.02.2026
################################

# This script can be used to scale the fraction unbound for pregnancy-----------

scale.fu = function(fu.NP, Age, PBP) {
  
  # fu.NP ... fu in nonpregnant reference subjects; numerical input
  
  # Age   ... Age as defined for the pregnant individual in PK-Sim in year(s)
  
  # PBP   ... Protein binding partner of the drug; input must be either "Albumin" or "AAG"
  
  GA = (Age - 30)*52 # Gestational age in weeks
  
  FA = GA - 2 # Fertilization age of pregnant woman in weeks (= gestational age - 2 weeks); numerical input between 0 and 38.9
  
  
  MW.Albumin = 67000   # Molecular weight of albumin
  
  MW.AAG = 44100       # Molecular weight of AAG
  
  
  
  Albumin = function(FA) (14.73261*exp(-0.04537584*FA) + 31.66739) /MW.Albumin*1E6      # Albumin concentration in µM
  
  AAG = function(FA) ((0.0768177*FA^2 -5.731431*FA)/1000 + 0.7012) /MW.AAG*1E6          # AAG concentration in µM
  
  
  
  P.NP = ifelse(PBP == "Albumin", Albumin(0), AAG(0))
  
  
  Ka.NP = (1- fu.NP)/(fu.NP * P.NP)
  
  
  
  fu.P = 1/(1+Ka.NP*ifelse(PBP == "Albumin", Albumin(FA), AAG(FA)))
  
  
  
  return(signif(fu.P, 2))
  
}   # scale fu via either albumin or AAG conc (assumption: drug binds only to one protein; either to albumin or to AAG)
# Aspirin
# 36wk = 0.68 yr
scale.fu(fu.NP = 0.417,
         Age = 30.68,
         PBP = "Albumin")
scale.fu(fu.NP = 0.1,
         Age = 30.68,
         PBP = "Albumin")

# 12wk = 0.68 yr
scale.fu(fu.NP = 0.417,
         Age = 30.23,
         PBP = "Albumin")
scale.fu(fu.NP = 0.1,
         Age = 30.23,
         PBP = "Albumin")

# 27wk = 0.51 yr
scale.fu(fu.NP = 0.417,
         Age = 30.51,
         PBP = "Albumin")
scale.fu(fu.NP = 0.1,
         Age = 30.51,
         PBP = "Albumin")

# 25wk = 0.47 yr
scale.fu(fu.NP = 0.417,
         Age = 30.47,
         PBP = "Albumin")
scale.fu(fu.NP = 0.1,
         Age = 30.47,
         PBP = "Albumin")
