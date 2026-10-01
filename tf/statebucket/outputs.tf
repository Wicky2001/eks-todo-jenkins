###############################################################################
# S3 Bucket
###############################################################################
output "state_bucket_id" {
  value = aws_s3_bucket.state.id
}

output "state_bucket_region" {
  value = aws_s3_bucket.state.region
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}