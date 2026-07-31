# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
resource "aws_codepipeline" "aft_codecommit_customizations_codepipeline" {
  count         = local.vcs.is_codecommit ? 1 : 0
  name          = "${var.account_id}-customizations-pipeline"
  role_arn      = data.aws_iam_role.aft_codepipeline_customizations_role.arn
  pipeline_type = "V2"

  artifact_store {
    location = data.aws_s3_bucket.aft_codepipeline_customizations_bucket.id
    type     = "S3"

    encryption_key {
      id   = data.aws_kms_alias.aft_key.arn
      type = "KMS"
    }
  }

  ##############################################################
  # Source
  ##############################################################
  stage {
    name = "Source"

    action {
      name             = "aft-global-customizations"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source-aft-global-customizations"]

      configuration = {
        RepositoryName       = data.aws_ssm_parameter.aft_global_customizations_repo_name.value
        BranchName           = data.aws_ssm_parameter.aft_global_customizations_repo_branch.value
        PollForSourceChanges = false
      }
    }

    action {
      name             = "aft-account-customizations"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source-aft-account-customizations"]

      configuration = {
        RepositoryName       = data.aws_ssm_parameter.aft_account_customizations_repo_name.value
        BranchName           = data.aws_ssm_parameter.aft_account_customizations_repo_branch.value
        PollForSourceChanges = false
      }
    }
  }

  ##############################################################
  # Plan-AFT-Global-Customizations
  ##############################################################

  stage {
    name = "Global-Customizations"
    action {
      name             = "Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source-aft-global-customizations"]
      output_artifacts = ["global-customizations-plan"]
      version          = "1"
      run_order        = "2"
      namespace        = "GlobalPlanVars"
      configuration = {
        ProjectName = var.aft_global_customizations_terraform_codebuild_name
        EnvironmentVariables = jsonencode([
          {
            name  = "VENDED_ACCOUNT_ID",
            value = var.account_id,
            type  = "PLAINTEXT"
          },
          {
            name  = "TF_COMMAND",
            value = "plan",
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }
  ##############################################################
  # Approve-and-Apply-AFT-Global-Customizations
  ##############################################################
  stage {
    name = "Global-Customizations-Apply"

    before_entry {
      condition {
        result = "SKIP"
        rule {
          name = "SkipWhenNoChanges"
          rule_type_id {
            category = "Rule"
            owner    = "AWS"
            provider = "VariableCheck"
            version  = "1"
          }
          configuration = {
            Variable = "#{GlobalPlanVars.TF_PLAN_CHANGES}"
            Value    = "true"
            Operator = "EQ"
          }
        }
      }
    }

    action {
      name               = "Approval"
      category           = "Approval"
      owner              = "AWS"
      provider           = "Manual"
      version            = "1"
      run_order          = "1"
      timeout_in_minutes = data.aws_ssm_parameter.aft_customizations_approval_timeout.value
      configuration = {
        NotificationArn    = data.aws_ssm_parameter.aft_customizations_approval_sns_topic_arn.value
        ExternalEntityLink = "#{GlobalPlanVars.TF_PLAN_LOGS_URL}"
        CustomData         = "Global customizations for account #{GlobalPlanVars.VENDED_ACCOUNT_NAME} (${var.account_id}) is awaiting review. Open the review link to inspect the terraform plan logs before approving. Expires ${data.aws_ssm_parameter.aft_customizations_approval_timeout.value} minutes after plan completion."
      }
    }

    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["global-customizations-plan"]
      version         = "1"
      run_order       = "2"
      configuration = {
        ProjectName = var.aft_global_customizations_terraform_codebuild_name
        EnvironmentVariables = jsonencode([
          {
            name  = "VENDED_ACCOUNT_ID",
            value = var.account_id,
            type  = "PLAINTEXT"
          },
          {
            name  = "TF_COMMAND",
            value = "apply",
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }
  ##############################################################
  # Plan-AFT-Account-Customizations
  ##############################################################
  stage {
    name = "Account-Customizations"

    action {
      name             = "Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source-aft-account-customizations"]
      output_artifacts = ["account-customizations-plan"]
      version          = "1"
      run_order        = "2"
      namespace        = "AccountPlanVars"
      configuration = {
        ProjectName = var.aft_account_customizations_terraform_codebuild_name
        EnvironmentVariables = jsonencode([
          {
            name  = "VENDED_ACCOUNT_ID",
            value = var.account_id,
            type  = "PLAINTEXT"
          },
          {
            name  = "TF_COMMAND",
            value = "plan",
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }
  ##############################################################
  # Approve-and-Apply-AFT-Account-Customizations
  ##############################################################
  stage {
    name = "Account-Customizations-Apply"

    before_entry {
      condition {
        result = "SKIP"
        rule {
          name = "SkipWhenNoChanges"
          rule_type_id {
            category = "Rule"
            owner    = "AWS"
            provider = "VariableCheck"
            version  = "1"
          }
          configuration = {
            Variable = "#{AccountPlanVars.TF_PLAN_CHANGES}"
            Value    = "true"
            Operator = "EQ"
          }
        }
      }
    }

    action {
      name               = "Approval"
      category           = "Approval"
      owner              = "AWS"
      provider           = "Manual"
      version            = "1"
      run_order          = "1"
      timeout_in_minutes = data.aws_ssm_parameter.aft_customizations_approval_timeout.value
      configuration = {
        NotificationArn    = data.aws_ssm_parameter.aft_customizations_approval_sns_topic_arn.value
        ExternalEntityLink = "#{AccountPlanVars.TF_PLAN_LOGS_URL}"
        CustomData         = "Account customizations for account #{AccountPlanVars.VENDED_ACCOUNT_NAME} (${var.account_id}) is awaiting review. Open the review link to inspect the terraform plan logs before approving. Expires ${data.aws_ssm_parameter.aft_customizations_approval_timeout.value} minutes after plan completion."
      }
    }

    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["account-customizations-plan"]
      version         = "1"
      run_order       = "2"
      configuration = {
        ProjectName = var.aft_account_customizations_terraform_codebuild_name
        EnvironmentVariables = jsonencode([
          {
            name  = "VENDED_ACCOUNT_ID",
            value = var.account_id,
            type  = "PLAINTEXT"
          },
          {
            name  = "TF_COMMAND",
            value = "apply",
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }
}

moved {
  from = aws_codepipeline.aft_codestar_customizations_codepipeline
  to   = aws_codepipeline.aft_codeconnections_customizations_codepipeline
}
resource "aws_codepipeline" "aft_codeconnections_customizations_codepipeline" {
  count         = local.vcs.is_codecommit ? 0 : 1
  name          = "${var.account_id}-customizations-pipeline"
  role_arn      = data.aws_iam_role.aft_codepipeline_customizations_role.arn
  pipeline_type = "V2"

  artifact_store {
    location = data.aws_s3_bucket.aft_codepipeline_customizations_bucket.id
    type     = "S3"

    encryption_key {
      id   = data.aws_kms_alias.aft_key.arn
      type = "KMS"
    }
  }

  ##############################################################
  # Source
  ##############################################################
  stage {
    name = "Source"

    action {
      name             = "aft-global-customizations"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source-aft-global-customizations"]

      configuration = {
        ConnectionArn        = data.aws_ssm_parameter.codeconnections_connection_arn.value
        FullRepositoryId     = data.aws_ssm_parameter.aft_global_customizations_repo_name.value
        BranchName           = data.aws_ssm_parameter.aft_global_customizations_repo_branch.value
        DetectChanges        = false
        OutputArtifactFormat = "CODE_ZIP"
      }
    }

    action {
      name             = "aft-account-customizations"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source-aft-account-customizations"]

      configuration = {
        ConnectionArn        = data.aws_ssm_parameter.codeconnections_connection_arn.value
        FullRepositoryId     = data.aws_ssm_parameter.aft_account_customizations_repo_name.value
        BranchName           = data.aws_ssm_parameter.aft_account_customizations_repo_branch.value
        DetectChanges        = false
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  ##############################################################
  # Plan-AFT-Global-Customizations
  ##############################################################

  stage {
    name = "AFT-Global-Customizations"

    action {
      name             = "Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source-aft-global-customizations"]
      output_artifacts = ["global-customizations-plan"]
      version          = "1"
      run_order        = "2"
      namespace        = "GlobalPlanVars"
      configuration = {
        ProjectName = var.aft_global_customizations_terraform_codebuild_name
        EnvironmentVariables = jsonencode([
          {
            name  = "VENDED_ACCOUNT_ID",
            value = var.account_id,
            type  = "PLAINTEXT"
          },
          {
            name  = "TF_COMMAND",
            value = "plan",
            type  = "PLAINTEXT"
          }
        ])
      }
    }

  }
  ##############################################################
  # Approve-and-Apply-AFT-Global-Customizations
  ##############################################################
  stage {
    name = "AFT-Global-Customizations-Apply"

    before_entry {
      condition {
        result = "SKIP"
        rule {
          name = "SkipWhenNoChanges"
          rule_type_id {
            category = "Rule"
            owner    = "AWS"
            provider = "VariableCheck"
            version  = "1"
          }
          configuration = {
            Variable = "#{GlobalPlanVars.TF_PLAN_CHANGES}"
            Value    = "true"
            Operator = "EQ"
          }
        }
      }
    }

    action {
      name               = "Approval"
      category           = "Approval"
      owner              = "AWS"
      provider           = "Manual"
      version            = "1"
      run_order          = "1"
      timeout_in_minutes = data.aws_ssm_parameter.aft_customizations_approval_timeout.value
      configuration = {
        NotificationArn    = data.aws_ssm_parameter.aft_customizations_approval_sns_topic_arn.value
        ExternalEntityLink = "#{GlobalPlanVars.TF_PLAN_LOGS_URL}"
        CustomData         = "Global customizations for account #{GlobalPlanVars.VENDED_ACCOUNT_NAME} (${var.account_id}) is awaiting review. Open the review link to inspect the terraform plan logs before approving. Expires ${data.aws_ssm_parameter.aft_customizations_approval_timeout.value} minutes after plan completion."
      }
    }

    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["global-customizations-plan"]
      version         = "1"
      run_order       = "2"
      configuration = {
        ProjectName = var.aft_global_customizations_terraform_codebuild_name
        EnvironmentVariables = jsonencode([
          {
            name  = "VENDED_ACCOUNT_ID",
            value = var.account_id,
            type  = "PLAINTEXT"
          },
          {
            name  = "TF_COMMAND",
            value = "apply",
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }
  ##############################################################
  # Plan-AFT-Account-Customizations
  ##############################################################

  stage {
    name = "AFT-Account-Customizations"
    action {
      name             = "Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source-aft-account-customizations"]
      output_artifacts = ["account-customizations-plan"]
      version          = "1"
      run_order        = "2"
      namespace        = "AccountPlanVars"
      configuration = {
        ProjectName = var.aft_account_customizations_terraform_codebuild_name
        EnvironmentVariables = jsonencode([
          {
            name  = "VENDED_ACCOUNT_ID",
            value = var.account_id,
            type  = "PLAINTEXT"
          },
          {
            name  = "TF_COMMAND",
            value = "plan",
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }
  ##############################################################
  # Approve-and-Apply-AFT-Account-Customizations
  ##############################################################
  stage {
    name = "AFT-Account-Customizations-Apply"

    before_entry {
      condition {
        result = "SKIP"
        rule {
          name = "SkipWhenNoChanges"
          rule_type_id {
            category = "Rule"
            owner    = "AWS"
            provider = "VariableCheck"
            version  = "1"
          }
          configuration = {
            Variable = "#{AccountPlanVars.TF_PLAN_CHANGES}"
            Value    = "true"
            Operator = "EQ"
          }
        }
      }
    }

    action {
      name               = "Approval"
      category           = "Approval"
      owner              = "AWS"
      provider           = "Manual"
      version            = "1"
      run_order          = "1"
      timeout_in_minutes = data.aws_ssm_parameter.aft_customizations_approval_timeout.value
      configuration = {
        NotificationArn    = data.aws_ssm_parameter.aft_customizations_approval_sns_topic_arn.value
        ExternalEntityLink = "#{AccountPlanVars.TF_PLAN_LOGS_URL}"
        CustomData         = "Account customizations for account #{AccountPlanVars.VENDED_ACCOUNT_NAME} (${var.account_id}) is awaiting review. Open the review link to inspect the terraform plan logs before approving. Expires ${data.aws_ssm_parameter.aft_customizations_approval_timeout.value} minutes after plan completion."
      }
    }

    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["account-customizations-plan"]
      version         = "1"
      run_order       = "2"
      configuration = {
        ProjectName = var.aft_account_customizations_terraform_codebuild_name
        EnvironmentVariables = jsonencode([
          {
            name  = "VENDED_ACCOUNT_ID",
            value = var.account_id,
            type  = "PLAINTEXT"
          },
          {
            name  = "TF_COMMAND",
            value = "apply",
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }
}
