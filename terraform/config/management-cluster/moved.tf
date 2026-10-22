# MC ZOA Lambda used count = (zoa_lambda_ecr_url != "") before #853; standing env state
# may still reference module.zoa_lambda[0].*
moved {
  from = module.zoa_lambda[0]
  to   = module.zoa_lambda
}
