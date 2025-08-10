import json
import boto3
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
lambda_client = boto3.client('lambda')

def update_todo_status(table, todo_id, created_at):
    #Update todo item status in DynamoDB
    try:
        response = table.update_item(
            Key={
                'id': todo_id,
                'created_at': created_at
            },
            UpdateExpression='SET #status = :status, processed_at = :processed_at, processed_by = :processed_by',
            ExpressionAttributeNames={
                '#status': 'status'
            },
            ExpressionAttributeValues={
                ':status': 'processed',
                ':processed_at': datetime.now().isoformat(),
                ':processed_by': 'Serverless ProcessTodo Lambda'
            },
            ReturnValues='UPDATED_NEW'
        )
        return True
    except Exception as e:
        print(f"Error updating TODO status: {str(e)}")
        return False

def invoke_image_processor(todo_data):
    """
    Call imageProcessor function to create image
    """
    try:
        # Get stage and build function name
        stage = os.environ.get('STAGE', 'dev')
        function_name = f"todo-serverless-service-{stage}-imageProcessor"
        
        print(f"🔍 DEBUG - Stage from env: '{stage}'")
        print(f"🔍 DEBUG - Function name: '{function_name}'")
        print(f"🔍 DEBUG - AWS Region: {os.environ.get('AWS_REGION', 'not-set')}")
        
        # Prepare payload for imageProcessor
        payload = {
            'trigger': 'processTodo',
            'todo_data': todo_data,
            'timestamp': datetime.now().isoformat()
        }
        
        print(f"🔍 DEBUG - Payload: {json.dumps(payload, indent=2)}")
        print(f"🚀 Invoking imageProcessor: {function_name}")
        
        # Invoke imageProcessor 
        response = lambda_client.invoke(
            FunctionName=function_name,
            InvocationType='Event',  
            Payload=json.dumps(payload)
        )
        
        print(f"✅ ImageProcessor response: StatusCode={response['StatusCode']}")
        print(f"✅ ImageProcessor response payload: {response.get('Payload', 'No payload').read().decode() if response.get('Payload') else 'No payload'}")
        
        return True
        
    except Exception as e:
        print(f"❌ Error invoking imageProcessor: {str(e)}")
        print(f"❌ Error type: {type(e).__name__}")
        import traceback
        print(f"❌ Traceback: {traceback.format_exc()}")
        return False

def process_single_todo(record, table):
    """
    Process a single TODO from SQS message
    """
    try:
        todo_data = json.loads(record['body'])
        todo_id = todo_data['id']
        created_at = todo_data['created_at']
        
        print(f"Processing TODO: {todo_id}")
        
        # Update TODO status in DynamoDB
        if not update_todo_status(table, todo_id, created_at):
            print(f"Failed to update TODO {todo_id} status")
            return False
        
        print(f"TODO {todo_id} status updated to 'processed'")
        
        # Invoke imageProcessor 
        if not invoke_image_processor(todo_data):
            print(f"Warning: imageProcessor invocation failed for TODO {todo_id}")
                    
        print(f"TODO {todo_id} processed successfully")
        return True
        
    except Exception as e:
        print(f"Error processing TODO: {str(e)}")
        return False

def handler(event, context):
    """
    Process TODO items from SQS and trigger image creation
    Simple version - no DLQ, just log errors and continue
    """
    print("=== ProcessTodo Started (SQS Trigger) ===")
    print(f"Processing {len(event['Records'])} messages")
    
    table = dynamodb.Table(os.environ['TODO_TABLE'])
    processed_count = 0
    failed_count = 0
    
    try:
        # Process each SQS message
        for record in event['Records']:
            if process_single_todo(record, table):
                processed_count += 1
            else:
                failed_count += 1
                print(f"Failed to process message: {record.get('messageId', 'unknown')}")
        
        print(f"Processing completed: {processed_count} successful, {failed_count} failed")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'processed': processed_count,
                'failed': failed_count,
                'message': f'Processed {processed_count} TODOs successfully, {failed_count} failed (logged)',
                'success': True
            })
        }
        
    except Exception as e:
        print(f"Error in processTodo handler: {str(e)}")
        # Even in case of general handler error, return success to avoid retries
        return {
            'statusCode': 200,
            'body': json.dumps({
                'success': False,
                'error': str(e),
                'message': 'Error in processTodo handler - logged for review',
                'processed': processed_count,
                'failed': failed_count
            })
        }