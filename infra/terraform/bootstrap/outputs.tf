output "state_bucket_name" {
  description = "Name of the S3 bucket - use this as the backend 'bucket' value for the root module"
  value       = aws_s3_bucket.tf_state.id
}

output "lock_table_name" {
  description = "Name of the DynamoDB table - use this as the backend 'dynamodb_table' value for the root module"
  value       = aws_dynamodb_table.tf_lock.name
}
