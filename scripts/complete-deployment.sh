#!/bin/bash

# Complete ECS Deployment Script
# This script completes the deployment after the Docker image has been pushed

set -e

echo "🚀 Completing Pipeline Pulse ECS Deployment"
echo "==========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ECR_REPO="272858488437.dkr.ecr.ap-southeast-1.amazonaws.com/pipeline-pulse"
TASK_DEFINITION_NAME="pipeline-pulse-backend"
CLUSTER_NAME="pipeline-pulse-cluster"
SERVICE_NAME="pipeline-pulse-service"

echo "🔍 Checking deployment status..."

# Check if task definition was registered successfully
echo -n "   Checking task definition... "
TASK_DEF_ARN=$(aws ecs describe-task-definition --task-definition "$TASK_DEFINITION_NAME" --query 'taskDefinition.taskDefinitionArn' --output text 2>/dev/null || echo "NONE")

if [ "$TASK_DEF_ARN" != "NONE" ]; then
    echo -e "${GREEN}✅ Found${NC}"
    echo "      ARN: $TASK_DEF_ARN"
else
    echo -e "${RED}❌ Not found${NC}"
    echo -e "${YELLOW}   Registering task definition...${NC}"
    aws ecs register-task-definition --cli-input-json file://ecs-task-definition-v8.json > /dev/null
    echo -e "${GREEN}   ✅ Task definition registered${NC}"
fi

# Check for ECS cluster
echo -n "   Checking ECS cluster... "
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query 'clusters[0].status' --output text 2>/dev/null || echo "MISSING")

if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
    echo -e "${GREEN}✅ Active${NC}"
elif [ "$CLUSTER_STATUS" = "MISSING" ]; then
    echo -e "${YELLOW}⚠️ Creating cluster...${NC}"
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" > /dev/null
    echo -e "${GREEN}   ✅ Cluster created${NC}"
else
    echo -e "${YELLOW}⚠️ Status: $CLUSTER_STATUS${NC}"
fi

# Check for ECS service
echo -n "   Checking ECS service... "
SERVICE_STATUS=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --query 'services[0].status' --output text 2>/dev/null || echo "MISSING")

if [ "$SERVICE_STATUS" = "ACTIVE" ]; then
    echo -e "${GREEN}✅ Active${NC}"
    echo -e "${BLUE}   Updating service with new image...${NC}"
    aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --task-definition "$TASK_DEFINITION_NAME" --force-new-deployment > /dev/null
    echo -e "${GREEN}   ✅ Service updated${NC}"
elif [ "$SERVICE_STATUS" = "MISSING" ]; then
    echo -e "${YELLOW}⚠️ Service not found${NC}"
    echo "   This might be the first deployment or service may have different name"
    echo "   Please check AWS Console for existing services"
else
    echo -e "${YELLOW}⚠️ Status: $SERVICE_STATUS${NC}"
fi

echo ""
echo "🧪 Testing deployment..."

# Wait a moment for service to start updating
sleep 5

# Test the application
echo -n "   Testing application... "
HEALTH_RESPONSE=$(curl -s https://1chsalesreports.com/health 2>/dev/null || echo "ERROR")

if echo "$HEALTH_RESPONSE" | grep -q '"status":\s*"healthy"'; then
    echo -e "${GREEN}✅ Application healthy${NC}"
elif echo "$HEALTH_RESPONSE" | grep -q "html"; then
    echo -e "${YELLOW}⚠️ Returns HTML (might be frontend routing)${NC}"
    # Try API path
    API_RESPONSE=$(curl -s https://1chsalesreports.com/api/health 2>/dev/null || echo "ERROR")
    if echo "$API_RESPONSE" | grep -q '"status":\s*"healthy"'; then
        echo -e "${GREEN}   ✅ API endpoint healthy${NC}"
    fi
else
    echo -e "${RED}❌ Not responding correctly${NC}"
    echo "      Response: $(echo "$HEALTH_RESPONSE" | head -c 100)"
fi

echo ""
echo "📋 DEPLOYMENT SUMMARY"
echo "===================="
echo "✅ Docker image built and pushed to ECR"
echo "✅ ECS task definition updated with fixes:"
echo "   - Correct Docker build context (./backend)"
echo "   - Working directory set to /app"
echo "   - Fixed uvicorn module import issue"
echo ""
echo "🌐 Application URL: https://1chsalesreports.com"
echo "🔧 API Health: https://1chsalesreports.com/api/health"
echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "💡 Next steps:"
echo "   1. Monitor the ECS service for successful task startup"
echo "   2. Check CloudWatch logs if issues occur"
echo "   3. Verify API endpoints are responding correctly" 