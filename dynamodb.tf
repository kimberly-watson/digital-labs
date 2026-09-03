# ---------------------------------------------------------------------------
# Request queue: every lab request submitted through the portal lands here.
# CodeBuild reads this table at apply time to build the full `labs` map,
# so state always reflects every request ever made, not just the latest one.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "lab_requests" {
  name         = "digital-labs-requests"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "lab_key"

  attribute {
    name = "lab_key"
    type = "S"
  }

  tags = {
    Project = "digital-labs"
  }
}
