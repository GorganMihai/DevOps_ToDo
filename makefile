SHELL := /bin/bash 

# ============================================
# CHANGE THIS TO SWITCH ENVIRONMENT
# ============================================
ENVIRONMENT := dev
# Options: dev, stage, prod

# Core Configuration
SERVICE_NAME := todo-serverless-service

# Dynamic Configuration - Extracted from YAML with Python
ifeq ($(OS),Windows_NT)
    # Windows: Use Python to extract values
    VPC := $(shell python -c "import yaml; print(yaml.safe_load(open('config/$(ENVIRONMENT).yml'))['vpcId'])")
    SUBNET := $(shell python -c "import yaml; d=yaml.safe_load(open('config/$(ENVIRONMENT).yml')); print(d['privateSubnetIds'][0])")
    REGION := $(shell python -c "import yaml; d=yaml.safe_load(open('config/$(ENVIRONMENT).yml')); print(d.get('region', 'eu-west-1'))")
else
    # Unix/Linux/Mac: Use Python too for consistency
    VPC := $(shell python3 -c "import yaml; print(yaml.safe_load(open('config/$(ENVIRONMENT).yml'))['vpcId'])")
    SUBNET := $(shell python3 -c "import yaml; d=yaml.safe_load(open('config/$(ENVIRONMENT).yml')); print(d['privateSubnetIds'][0])")
    REGION := $(shell python3 -c "import yaml; d=yaml.safe_load(open('config/$(ENVIRONMENT).yml')); print(d.get('region', 'eu-west-1'))")
endif

# Derived Variables - All based on ENVIRONMENT
TABLE_NAME := $(SERVICE_NAME)-$(ENVIRONMENT)-todos
BUCKET_PREFIX := $(SERVICE_NAME)-$(ENVIRONMENT)-artifacts
FUNCTION_PREFIX := $(SERVICE_NAME)-$(ENVIRONMENT)
STAGE := $(ENVIRONMENT)

# Detect OS
ifeq ($(OS),Windows_NT)
    DETECTED_OS := Windows
    CHECK_CMD := where
    NULL_DEVICE := >nul 2>&1
else
    DETECTED_OS := Unix
    CHECK_CMD := command -v
    NULL_DEVICE := >/dev/null 2>&1
endif

.PHONY: hello setup deploy test_createTodo info remove logs test_functions check_deps clean_data show_table show_s3 test_all show_config

# Check system dependencies
check_deps:
	@echo ==================================================
	@echo     System Check - $(DETECTED_OS)
	@echo ==================================================
ifeq ($(OS),Windows_NT)
	@where serverless $(NULL_DEVICE) || (echo ERROR: Serverless Framework not found. Install with: npm install -g serverless && exit 1)
	@where aws $(NULL_DEVICE) || (echo ERROR: AWS CLI not found. Install from: https://aws.amazon.com/cli/ && exit 1)
	@aws sts get-caller-identity $(NULL_DEVICE) || (echo ERROR: AWS credentials not configured. Run: aws configure && exit 1)
	@python -c "import yaml" $(NULL_DEVICE) || (echo ERROR: Python library pyyaml not found. Install with: pip install pyyaml && exit 1)
else
	@$(CHECK_CMD) serverless $(NULL_DEVICE) || (echo ERROR: Serverless Framework not found. Install with: npm install -g serverless && exit 1)
	@$(CHECK_CMD) aws $(NULL_DEVICE) || (echo ERROR: AWS CLI not found. Install from: https://aws.amazon.com/cli/ && exit 1)
	@aws sts get-caller-identity $(NULL_DEVICE) || (echo ERROR: AWS credentials not configured. Run: aws configure && exit 1)
	@python3 -c "import yaml" $(NULL_DEVICE) || (echo ERROR: Python library pyyaml not found. Install with: pip3 install pyyaml && exit 1)
endif
	@echo OK: All dependencies found
	@echo OK: AWS credentials configured
	@echo.



hello:
	@echo ==================================================
	@echo     Serverless TODO Service - Make Commands
	@echo ==================================================
	@echo PLATFORM: $(DETECTED_OS)
	@echo ACTIVE ENVIRONMENT: $(ENVIRONMENT)
	@echo REGION: $(REGION)
	@echo VPC: $(VPC)
	@echo SUBNET: $(SUBNET)
	@echo ==================================================
	@echo To switch environment, edit ENVIRONMENT variable in Makefile
	@echo Currently using: config/$(ENVIRONMENT).yml
	@echo ==================================================
	@echo Available commands:
	@echo   make show_config      - Show current configuration
	@echo   make check_deps       - Check system dependencies
	@echo   make setup            - Install serverless plugins
	@echo   make deploy           - Deploy to $(ENVIRONMENT) environment
	@echo   make info             - Show $(ENVIRONMENT) deployment info
	@echo   make test_createTodo  - Test createTodo function
	@echo   make test_functions   - Test all Lambda functions
	@echo   make show_table       - Show DynamoDB table content
	@echo   make show_s3          - Show S3 bucket content
	@echo   make test_all         - Test all functions and show data
	@echo   make logs             - Watch processTodo logs
	@echo   make clean_data       - Clean S3 and DynamoDB data
	@echo   make remove           - Remove $(ENVIRONMENT) deployment
	@echo.
	@echo Examples:
	@echo   make setup
	@echo   make deploy
	@echo   make test_createTodo
	@echo.

show_config:
	@echo ==================================================
	@echo     Current Configuration Details
	@echo ==================================================
	@echo ENVIRONMENT: $(ENVIRONMENT)
	@echo CONFIG FILE: config/$(ENVIRONMENT).yml
	@echo ==================================================
	@echo Extracted from config:
	@echo   REGION: $(REGION)
	@echo   VPC ID: $(VPC)
	@echo   SUBNET: $(SUBNET)
	@echo ==================================================
	@echo Generated names:
	@echo   DynamoDB Table: $(TABLE_NAME)
	@echo   S3 Bucket Prefix: $(BUCKET_PREFIX)
	@echo   Lambda Prefix: $(FUNCTION_PREFIX)
	@echo.

setup:
	@echo [SETUP] Checking pyyaml installation...
ifeq ($(OS),Windows_NT)
	@python -c "import yaml" 2>nul || (echo pyyaml is not installed, proceeding with installation... && pip install pyyaml && python -c "import yaml" 2>nul || (echo ERROR: pyyaml installation failed. && exit 1))
else
	@python3 -c "import yaml" >/dev/null 2>&1 || (echo pyyaml is not installed, proceeding with installation... && pip3 install pyyaml && python3 -c "import yaml" >/dev/null 2>&1 || (echo ERROR: pyyaml installation failed. && exit 1))
endif
	@echo [SETUP] Installing Serverless plugins...
	@serverless plugin install -n serverless-python-requirements
	@echo [SETUP] Setup completed.
	@$(MAKE) check_deps


deploy:
	@echo ==================================================
	@echo [DEPLOY] Deploying to $(ENVIRONMENT) environment
	@echo ==================================================
	@echo Region: $(REGION)
	@echo VPC: $(VPC)
	@echo SUBNET: $(SUBNET)
	@echo.
	@echo [DEPLOY] Ensuring VPC DNS settings are enabled...
	@aws ec2 modify-vpc-attribute --vpc-id $(VPC) --enable-dns-support --region $(REGION)  || true
	@aws ec2 modify-vpc-attribute --vpc-id $(VPC) --enable-dns-hostnames --region $(REGION)  || true
	@echo [DEPLOY] Deploying TODO service to $(ENVIRONMENT) environment with VPC...
	@echo WARNING: VPC deployment may take longer due to VPC Endpoints
	@serverless deploy --stage $(STAGE) --region $(REGION)
	@echo [DEPLOY] Deployment to $(ENVIRONMENT) completed - 3 Lambda functions deployed in VPC.

test_createTodo:
	@echo [TEST] Running createTodo function in $(ENVIRONMENT) environment...
	@serverless invoke --function createTodo --stage $(STAGE) --region $(REGION) --log
	@echo [TEST] createTodo test completed.
	@echo Waiting 5 seconds for async processing...
ifeq ($(OS),Windows_NT)
	@timeout /t 5 >nul
else
	@sleep 5
endif
	@$(MAKE) --no-print-directory show_s3
	@$(MAKE) --no-print-directory show_table

info:
	@echo [INFO] Showing $(ENVIRONMENT) deployment info...
	@echo ==================================================
	@echo SERVERLESS DEPLOYMENT INFO - $(ENVIRONMENT)
	@echo ==================================================
	@serverless info --stage $(STAGE) --region $(REGION)

logs:
	@echo [LOGS] Watching processTodo logs in $(ENVIRONMENT) (Ctrl+C to stop)...
	@serverless logs --function processTodo --stage $(STAGE) --region $(REGION) --tail

remove:
	@echo ==================================================
	@echo [REMOVE] WARNING: This will remove the $(ENVIRONMENT) stack!
	@echo ==================================================
	@echo Stack to remove: $(SERVICE_NAME)-$(STAGE)
	@echo Region: $(REGION)
	@echo.
	@echo Press Ctrl+C in the next 5 seconds to cancel...
ifeq ($(OS),Windows_NT)
	@timeout /t 5 /nobreak >nul
else
	@sleep 5
endif
	@echo [REMOVE] Removing $(ENVIRONMENT) stack...
	@serverless remove --stage $(STAGE) --region $(REGION)
	@echo [REMOVE] $(ENVIRONMENT) stack removed.

test_functions:
	@echo ==================================================
	@echo [TEST] Testing all Lambda functions in $(ENVIRONMENT)
	@echo ==================================================
	@echo Environment: $(ENVIRONMENT)
	@echo Region: $(REGION)
	@echo.
	@echo --- Testing createTodo ---
	@serverless invoke --function createTodo --stage $(STAGE) --region $(REGION) --log || echo ERROR: createTodo failed
	@echo.
	@echo --- Testing imageProcessor ---
	@serverless invoke --function imageProcessor --stage $(STAGE) --region $(REGION) --log || echo ERROR: imageProcessor failed
	@echo.
	@echo Note: processTodo is SQS-triggered and tested via createTodo workflow
	@echo.

show_table:
	@echo ==================================================
	@echo [TABLE] DynamoDB Table Content - $(ENVIRONMENT)
	@echo ==================================================
	@echo Table: $(TABLE_NAME)
	@echo Region: $(REGION)
	@echo.
	@echo Table item count:
ifeq ($(OS),Windows_NT)
	-@aws dynamodb scan --table-name $(TABLE_NAME) --region $(REGION) --select COUNT --output text --query Count 2>nul || echo ERROR: Could not get item count
else
	-@aws dynamodb scan --table-name $(TABLE_NAME) --region $(REGION) --select COUNT --output text --query Count 2>/dev/null || echo ERROR: Could not get item count
endif
	@echo.
	@echo Table contents:
ifeq ($(OS),Windows_NT)
	-@aws dynamodb scan --table-name $(TABLE_NAME) --region $(REGION) --output text 2>nul || echo ERROR: Could not read table
else
	-@aws dynamodb scan --table-name $(TABLE_NAME) --region $(REGION) --projection-expression "TITLE, PROCESSED_BY" --output text 2>/dev/null || echo ERROR: Could not read table
endif
	@echo.

show_s3:
	@echo ==================================================
	@echo [S3] Bucket Content - Generated Images - $(ENVIRONMENT)
	@echo ==================================================
	@echo Getting AWS Account ID...
ifeq ($(OS),Windows_NT)
	@for /f %%i in ('aws sts get-caller-identity --query Account --output text 2^>nul') do @( \
		set ACCOUNT_ID=%%i && \
		echo Bucket: $(BUCKET_PREFIX)-%%i && \
		echo Region: $(REGION) && \
		echo. && \
		echo Objects: && \
		aws s3 ls s3://$(BUCKET_PREFIX)-%%i --recursive 2>nul || echo ERROR: Could not access bucket && \
		echo. \
	)
else
	@ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text 2>/dev/null) && \
	BUCKET_NAME="$(BUCKET_PREFIX)-$$ACCOUNT_ID" && \
	echo "Bucket: $$BUCKET_NAME" && \
	echo "Region: $(REGION)" && \
	echo && \
	echo "Objects:" && \
	aws s3 ls "s3://$$BUCKET_NAME" --recursive 2>/dev/null || echo "ERROR: Could not access bucket" && \
	echo && \
	echo "Direct URLs:" && \
	aws s3api list-objects-v2 --bucket "$$BUCKET_NAME" --query "Contents[?Size > '0'].Key" --output text 2>/dev/null | \
	while read -r key; do \
		if [ ! -z "$$key" ]; then \
			echo "https://$$BUCKET_NAME.s3.$(REGION).amazonaws.com/$$key"; \
		fi; \
	done || echo "No objects found or bucket not accessible"
endif
	@echo.

test_all:
	@echo ==================================================
	@echo COMPLETE TEST SUITE - $(ENVIRONMENT) ENVIRONMENT
	@echo ==================================================
	@echo.
	
	@echo ==================================================
	@echo 1. CONFIGURATION CHECK
	@echo ==================================================
	@$(MAKE) --no-print-directory show_config
	@echo.
	
	@echo ==================================================
	@echo 2. DEPLOYMENT INFO
	@echo ==================================================
	@$(MAKE) --no-print-directory info
	@echo.
	
	@echo ==================================================
	@echo 3. LAMBDA FUNCTIONS TEST 
	@echo ==================================================
	@$(MAKE) --no-print-directory test_functions
	@echo.
	
	@echo ==================================================
	@echo 4. DYNAMODB TABLE CONTENT
	@echo ==================================================
	@$(MAKE) --no-print-directory show_table
	@echo.
	
	@echo ==================================================
	@echo 5. S3 BUCKET CONTENT
	@echo ==================================================
	@$(MAKE) --no-print-directory show_s3
	@echo.
	
	@echo ==================================================
	@echo COMPLETE TEST SUITE FINISHED - $(ENVIRONMENT)
	@echo ==================================================
	@echo Summary:
	@echo - Environment: $(ENVIRONMENT)
	@echo - Region: $(REGION)
	@echo - 3 Lambda functions tested
	@echo - DynamoDB table content displayed
	@echo - S3 bucket content listed
	@echo.
	@echo Tips:
	@echo - Use 'make logs' to watch real-time processTodo logs
	@echo - Use 'make test_createTodo' to test end-to-end workflow
	@echo - Check AWS CloudWatch for detailed function logs
	@echo - Architecture: createTodo -\> SQS -\> processTodo -\> imageProcessor -\> S3
	@echo - All functions deployed in VPC with VPC Endpoints
	@echo.

clean_data:
	@echo ==================================================
	@echo [CLEAN] Deleting S3 objects and DynamoDB items in $(ENVIRONMENT)
	@echo ==================================================
	@echo Environment: $(ENVIRONMENT)
	@echo Region: $(REGION)
	@echo.
ifeq ($(OS),Windows_NT)
	@for /f %%i in ('aws sts get-caller-identity --query Account --output text 2^>nul') do @( \
		set "ACCOUNT_ID=%%i" && \
		set "BUCKET_NAME=$(BUCKET_PREFIX)-%%i" && \
		call echo Deleting all objects in S3 bucket: %%BUCKET_NAME%% && \
		call aws s3 rm s3://%%BUCKET_NAME%% --recursive || echo ERROR: Could not clean S3 bucket \
	)

	@echo Fetching id and created_at keys from DynamoDB...
	@aws dynamodb scan --table-name $(TABLE_NAME) --region $(REGION) --query "Items[].[id.S, created_at.S]" --output text > items.txt

	@for /f "tokens=1,2" %%A in (items.txt) do @( \
		echo Deleting item with id=%%A and created_at=%%B && \
		aws dynamodb delete-item --table-name $(TABLE_NAME) --region $(REGION) --key "{\"id\": {\"S\": \"%%A\"}, \"created_at\": {\"S\": \"%%B\"}}" \
	)

	@del items.txt
else
	@ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text 2>/dev/null) && \
	BUCKET_NAME="$(BUCKET_PREFIX)-$$ACCOUNT_ID" && \
	echo "Deleting all objects in S3 bucket: $$BUCKET_NAME" && \
	aws s3 rm "s3://$$BUCKET_NAME" --recursive || echo "ERROR: Could not clean S3 bucket"
	@aws dynamodb scan --table-name $(TABLE_NAME) --region $(REGION) --query "Items[].[id.S, created_at.S]" --output text | \
	while read id created_at; do \
		if [ ! -z "$$id" ] && [ ! -z "$$created_at" ]; then \
			echo "Deleting item with id=$$id and created_at=$$created_at"; \
			aws dynamodb delete-item --table-name $(TABLE_NAME) --region $(REGION) --key "{\"id\": {\"S\": \"$$id\"}, \"created_at\": {\"S\": \"$$created_at\"}}" || \
			echo "Failed to delete item with ID: $$id"; \
		fi; \
	done
endif
	@echo [CLEAN] Cleanup complete for $(ENVIRONMENT).

	@echo ==================================================
	@echo 	S3 BUCKET CONTENT - $(ENVIRONMENT)
	@echo ==================================================
	@$(MAKE) --no-print-directory show_s3
	@echo.

	@echo ==================================================
	@echo 	DYNAMODB TABLE CONTENT - $(ENVIRONMENT)
	@echo ==================================================
	@$(MAKE) --no-print-directory show_table
	@echo.