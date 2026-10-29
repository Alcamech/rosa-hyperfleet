moved {
  from = module.pipeline_notifications
  to   = module.codebuild_notifications
}

# The shared MC role is now always present instead of conditionally counted.
moved {
  from = aws_iam_role.mc_codebuild_role[0]
  to   = aws_iam_role.mc_codebuild_role
}

moved {
  from = aws_iam_role_policy.mc_codebuild_policy[0]
  to   = aws_iam_role_policy.mc_codebuild_policy
}
