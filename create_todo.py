import json
import boto3
import uuid
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

def handler(event, context):
    #Create TODO items - Manual trigger
    
    print("=== CreateTodo Started ===")
    
    # Create item
    todo = {
        'id': str(uuid.uuid4()),
        'created_at': datetime.now().isoformat(),
        'title': f"Serverless TODO - {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        'description': 'Created with simplified Serverless Framework approach - clean and efficient',
        'status': 'pending'
    }
    
    try:
        # Save to DynamoDB
        table = dynamodb.Table(os.environ['TODO_TABLE'])
        table.put_item(Item=todo)
        print("✅ TODO saved to DynamoDB")
        print(f"✅ Title: {todo['title']}")
        
        # Send to SQS
        message_response = sqs.send_message(
            QueueUrl=os.environ['PROCESSING_QUEUE_URL'],
            MessageBody=json.dumps(todo),
            MessageAttributes={
                'todoType': {
                    'StringValue': 'standard',
                    'DataType': 'String'
                }
            }
        )
        print("✅ Message sent to SQS")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'success': True,
                'message': 'TODO created successfully',
                'todo': {
                    'id': todo['id'],
                    'title': todo['title'],
                    'status': todo['status'],
                    'created_at': todo['created_at']
                },
                'sqs_message_id': message_response.get('MessageId'),
                'next_steps': [
                    'SQS will trigger processTodo Lambda',
                    'processTodo will update status and call imageProcessor',
                    'imageProcessor will create SVG and upload to S3'
                ]
            })
        }
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'success': False,
                'error': str(e),
                'message': 'Error creating TODO'
            })
        }