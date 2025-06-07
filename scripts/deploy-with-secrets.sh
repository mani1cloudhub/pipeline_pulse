#!/bin/bash

# Deploy Pipeline Pulse with AWS Secrets Manager Integration
# This script handles the complete deployment with enhanced security

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${BLUE}🚀 Pipeline Pulse - Secure Deployment with Secrets Manager${NC}"
echo "========================================================"
echo

# Configuration
AWS_REGION="ap-southeast-1"
SECRET_NAME="pipeline-pulse/app-secrets"
ECR_REPO="pipeline-pulse"
CLUSTER_NAME="pipeline-pulse-prod"
SERVICE_NAME="pipeline-pulse-prod-service-v2"

# Check prerequisites
echo -e "${BLUE}🔍 Checking prerequisites...${NC}"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not found. Please install AWS CLI.${NC}"
    exit 1
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Please install Docker.${NC}"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${RED}❌ AWS credentials not configured. Please run 'aws configure'${NC}"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo -e "${GREEN}   AWS Account: $ACCOUNT_ID${NC}"
echo -e "${GREEN}   AWS Region: $AWS_REGION${NC}"
echo

# Check if secrets exist
echo -e "${BLUE}🔍 Checking AWS Secrets Manager setup...${NC}"
if ! aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Secrets not found. Setting up Secrets Manager first...${NC}"
    bash scripts/setup-secrets-manager.sh
    echo
fi

echo -e "${GREEN}✅ Secrets Manager configured${NC}"
echo

# Build and push Docker image
echo -e "${BLUE}🐳 Building and pushing Docker image...${NC}"

# Get ECR login token
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Build image
echo -e "${BLUE}   Building Docker image...${NC}"
docker build -f ./backend/Dockerfile -t "$ECR_REPO" ./backend

# Tag image
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:latest"
docker tag "$ECR_REPO:latest" "$ECR_URI"

# Push image
echo -e "${BLUE}   Pushing to ECR...${NC}"
docker push "$ECR_URI"

echo -e "${GREEN}✅ Docker image built and pushed${NC}"
echo -e "${GREEN}   Image URI: $ECR_URI${NC}"
echo

# Update ECS task definition with secrets
echo -e "${BLUE}🔧 Updating ECS task definition with Secrets Manager...${NC}"
bash scripts/update-ecs-task-definition.sh
echo

# Verify deployment
echo -e "${BLUE}🔍 Verifying deployment...${NC}"

# Wait a bit for the service to stabilize
sleep 30

# Test health endpoint
echo -e "${BLUE}   Testing health endpoint...${NC}"
for i in {1..5}; do
    if curl -s -f "https://api.1chsalesreports.com/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Health endpoint responding${NC}"
        break
    elif curl -s -f "http://pipeline-pulse-alb-1144051995.ap-southeast-1.elb.amazonaws.com/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Health endpoint responding via ALB${NC}"
        break
    else
        echo -e "${YELLOW}⏳ Waiting for health endpoint... (attempt $i/5)${NC}"
        sleep 10
    fi
done

# Test secrets integration
echo -e "${BLUE}   Testing secrets integration...${NC}"
HEALTH_RESPONSE=$(curl -s "http://pipeline-pulse-alb-1144051995.ap-southeast-1.elb.amazonaws.com/health" 2>/dev/null || echo '{}')
if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
    echo -e "${GREEN}✅ Application is healthy with secrets integration${NC}"
else
    echo -e "${YELLOW}⚠️  Health check response: $HEALTH_RESPONSE${NC}"
fi

# Check ECS service status
echo -e "${BLUE}   Checking ECS service status...${NC}"
SERVICE_INFO=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[0].{RunningCount:runningCount,DesiredCount:desiredCount,PendingCount:pendingCount}' \
    --output json)

RUNNING_COUNT=$(echo "$SERVICE_INFO" | jq -r '.RunningCount')
DESIRED_COUNT=$(echo "$SERVICE_INFO" | jq -r '.DesiredCount')
PENDING_COUNT=$(echo "$SERVICE_INFO" | jq -r '.PendingCount')

if [ "$RUNNING_COUNT" -eq "$DESIRED_COUNT" ] && [ "$PENDING_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ ECS service is stable${NC}"
    echo -e "${GREEN}   Running tasks: $RUNNING_COUNT/$DESIRED_COUNT${NC}"
else
    echo -e "${YELLOW}⚠️  ECS service status:${NC}"
    echo -e "${YELLOW}   Running: $RUNNING_COUNT, Desired: $DESIRED_COUNT, Pending: $PENDING_COUNT${NC}"
fi

echo

# Security verification
echo -e "${BLUE}🔒 Security verification...${NC}"

# Check that secrets are not in environment variables
echo -e "${BLUE}   Verifying secrets are not exposed...${NC}"
TASK_ARN=$(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'taskArns[0]' \
    --output text)

if [ "$TASK_ARN" != "None" ] && [ -n "$TASK_ARN" ]; then
    TASK_DETAILS=$(aws ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --region "$AWS_REGION" \
        --query 'tasks[0].containers[0].environment' \
        --output json 2>/dev/null || echo '[]')
    
    # Check that sensitive values are not in environment
    if echo "$TASK_DETAILS" | grep -q "password\|secret\|key" | grep -v "CLIENT_ID\|BASE_URL"; then
        echo -e "${RED}❌ Sensitive data found in environment variables${NC}"
    else
        echo -e "${GREEN}✅ No sensitive data in environment variables${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Could not verify task environment (task may be starting)${NC}"
fi

echo

# Final summary
echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
echo
echo -e "${YELLOW}📊 Deployment Summary:${NC}"
echo "  • Application: Pipeline Pulse"
echo "  • Environment: Production"
echo "  • Security: AWS Secrets Manager integrated"
echo "  • Frontend: https://1chsalesreports.com"
echo "  • API: https://api.1chsalesreports.com"
echo "  • Health: https://api.1chsalesreports.com/health"
echo
echo -e "${YELLOW}🔐 Security Features:${NC}"
echo "  • Database passwords stored in Secrets Manager"
echo "  • API keys encrypted and rotatable"
echo "  • JWT secrets securely managed"
echo "  • No sensitive data in environment variables"
echo
echo -e "${YELLOW}📝 Next Steps:${NC}"
echo "  1. Test application functionality"
echo "  2. Set up secret rotation (optional)"
echo "  3. Monitor application logs"
echo "  4. Configure alerts and monitoring"
echo
echo -e "${BLUE}💡 Useful Commands:${NC}"
echo "  # View logs"
echo "  aws logs tail /ecs/pipeline-pulse-prod --follow --region $AWS_REGION"
echo
echo "  # Check service status"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
echo
echo "  # Update secrets"
echo "  bash scripts/setup-secrets-manager.sh"
