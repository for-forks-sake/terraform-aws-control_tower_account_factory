# SNS topic notified by the manual approval action in the per-account
# customizations pipelines (see sources/aft-customizations-common/templates/customizations_pipeline).
# Subscriptions are managed by operators outside of AFT.
resource "aws_sns_topic" "aft_customizations_approval" {
  name = "aft-customizations-approval-notifications"
  #tfsec:ignore:aws-sns-topic-encryption-use-cmk
  kms_master_key_id = var.sns_topic_enable_cmk_encryption ? var.aft_kms_key_id : "alias/aws/sns"
}
