#!/bin/bash

# Variables
BUCKET_NAME="exo-website"
WEBSITE_DIR="./website"
DOMAIN_NAME="exolabs.net"
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" --output text | cut -d'/' -f3)

# Check if the bucket exists
if ! aws s3 ls "s3://$BUCKET_NAME" > /dev/null 2>&1; then
  # Create the bucket
  aws s3 mb s3://$BUCKET_NAME
  
  # Set the S3 bucket to host a static website
  aws s3 website s3://$BUCKET_NAME --index-document index.html

  # Enable public access
  aws s3api put-public-access-block \
    --bucket $BUCKET_NAME \
    --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

  # Set bucket policy for public read access
  aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "PublicReadGetObject",
        "Effect": "Allow",
        "Principal": "*",
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::'"$BUCKET_NAME"'/*"
      }
    ]
  }'
fi

# Get the S3 bucket region
BUCKET_REGION=$(aws s3api get-bucket-location --bucket $BUCKET_NAME --output text)
if [ "$BUCKET_REGION" == "None" ]; then
  BUCKET_REGION="us-east-1"
fi
echo "Bucket region: $BUCKET_REGION"
# Get the correct S3 website endpoint for the region
case "$BUCKET_REGION" in
  "us-east-1")
    S3_WEBSITE_ENDPOINT="s3-website-us-east-1.amazonaws.com"
    S3_HOSTED_ZONE_ID="Z3AQBSTGFYJSTF"
    ;;
  "us-west-1")
    S3_WEBSITE_ENDPOINT="s3-website-us-west-1.amazonaws.com"
    S3_HOSTED_ZONE_ID="Z2F56UZL2M1ACD"
    ;;
  "us-west-2")
    S3_WEBSITE_ENDPOINT="s3-website-us-west-2.amazonaws.com"
    S3_HOSTED_ZONE_ID="Z3BJ6K6RIION7M"
    ;;
  "eu-west-1")
    S3_WEBSITE_ENDPOINT="s3-website-eu-west-1.amazonaws.com"
    S3_HOSTED_ZONE_ID="Z1BKCTXD74EZPE"
    ;;
  "eu-central-1")
    S3_WEBSITE_ENDPOINT="s3-website.eu-central-1.amazonaws.com"
    S3_HOSTED_ZONE_ID="Z21DNDUVLTQW6Q"
    ;;
  *)
    echo "Unsupported bucket region: $BUCKET_REGION"
    exit 1
    ;;
esac

# Check if the Route 53 record exists
if ! aws route53 list-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --query "ResourceRecordSets[?Name=='${DOMAIN_NAME}.' && Type=='A']" --output text | grep -q "${DOMAIN_NAME}"; then
  # Create Route 53 A record
  aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch '{
    "Changes": [
      {
        "Action": "CREATE",
        "ResourceRecordSet": {
          "Name": "'"$DOMAIN_NAME"'",
          "Type": "A",
          "AliasTarget": {
            "HostedZoneId": "'"$S3_HOSTED_ZONE_ID"'",
            "DNSName": "'"$S3_WEBSITE_ENDPOINT"'",
            "EvaluateTargetHealth": false
          }
        }
      }
    ]
  }'
  echo "Route 53 A record created for $DOMAIN_NAME"
else
  echo "Route 53 A record already exists for $DOMAIN_NAME"
fi

# Sync the website directory to the S3 bucket
aws s3 sync $WEBSITE_DIR s3://$BUCKET_NAME --delete

echo "Deployment to S3 bucket $BUCKET_NAME and Route 53 configuration completed successfully."