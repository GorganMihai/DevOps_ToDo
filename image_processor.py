import json
import os
import boto3
from datetime import datetime

s3 = boto3.client('s3')

def create_svg_image(width=500, height=500):
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    svg_content = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg width="{width}" height="{height}" xmlns="http://www.w3.org/2000/svg">
    <rect width="100%" height="100%" fill="red" />
    <text x="{width//2}" y="{height//2 - 20}" 
          font-family="Arial, sans-serif" font-size="36" font-weight="bold"
          fill="white" text-anchor="middle" dominant-baseline="middle">
        VOIS DevOps
    </text>
    <text x="{width//2}" y="{height//2 + 30}" 
          font-family="Arial, sans-serif" font-size="20"
          fill="white" text-anchor="middle" dominant-baseline="middle">
        {timestamp}
    </text>
</svg>'''
    
    return svg_content

def handler(event, context):
    print("=== ImageProcessor Started ===")
    
    try:
        width, height = 500, 500
        svg_content = create_svg_image(width, height)
        
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        filename = f"vois-devops-{timestamp}.svg"
        
        bucket_name = os.environ.get('S3_BUCKET_NAME')
        if not bucket_name:
            stage = os.environ.get('AWS_LAMBDA_FUNCTION_NAME', 'dev').split('-')[-2]
            account_id = context.invoked_function_arn.split(':')[4]
            bucket_name = f"todo-serverless-service-{stage}-artifacts-{account_id}"
        
        try:
            s3.put_object(
                Bucket=bucket_name,
                Key=f"images/{filename}",
                Body=svg_content.encode('utf-8'),
                ContentType='image/svg+xml'
            )
            
            s3_url = f"https://{bucket_name}.s3.{os.environ.get('AWS_REGION', 'eu-west-1')}.amazonaws.com/images/{filename}"
            print(f"✅ SVG uploaded: {s3_url}")
            
            upload_verified = True
            try:
                s3.head_object(Bucket=bucket_name, Key=f"images/{filename}")
            except:
                upload_verified = False
            
        except Exception as s3_error:
            print(f"❌ S3 upload failed: {s3_error}")
            s3_url = f"S3 upload failed: {str(s3_error)}"
            upload_verified = False
        
        result = {
            'image_created': True,
            'filename': filename,
            's3_url': s3_url,
            'upload_verified': upload_verified
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'success': True,
                'message': 'SVG image created successfully',
                'result': result
            })
        }
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'success': False,
                'error': str(e),
                'message': 'Error creating SVG image'
            })
        }