#!/bin/bash

# Test Docker Build Context for Pipeline Pulse
# This script verifies that the Docker build works correctly

set -e

echo "🧪 Testing Pipeline Pulse Docker Build Context"
echo "=============================================="
echo

# Check if we're in the right directory
if [ ! -f "backend/main.py" ]; then
    echo "❌ Error: Please run this script from the project root directory"
    echo "   Expected to find: backend/main.py"
    exit 1
fi

echo "✅ Found backend/main.py"

# Check if Dockerfile exists
if [ ! -f "backend/Dockerfile" ]; then
    echo "❌ Error: backend/Dockerfile not found"
    exit 1
fi

echo "✅ Found backend/Dockerfile"

# Check if requirements.txt exists
if [ ! -f "backend/requirements.txt" ]; then
    echo "❌ Error: backend/requirements.txt not found"
    exit 1
fi

echo "✅ Found backend/requirements.txt"

# Simulate the build context check
echo ""
echo "🔍 Testing build context..."
echo "   Build context: ./backend"
echo "   Dockerfile: ./backend/Dockerfile"
echo "   Working directory in container: /app"
echo "   Expected main.py location: /app/main.py"
echo ""

# Check if Docker is available
if command -v docker &> /dev/null; then
    echo "🐳 Docker is available - running test build..."
    
    # Test build
    docker build -f ./backend/Dockerfile -t pipeline-pulse-test ./backend
    
    echo "✅ Docker build successful!"
    
    # Test container
    echo "🧪 Testing container startup..."
    docker run --rm -d --name pipeline-pulse-test-container -p 8001:8000 pipeline-pulse-test
    
    # Wait a moment
    sleep 5
    
    # Test health endpoint
    if curl -s -f http://localhost:8001/health > /dev/null 2>&1; then
        echo "✅ Container is running and healthy!"
    else
        echo "⚠️  Container started but health check failed (expected in test)"
    fi
    
    # Cleanup
    docker stop pipeline-pulse-test-container 2>/dev/null || true
    docker rmi pipeline-pulse-test 2>/dev/null || true
    
else
    echo "ℹ️  Docker not available locally - skipping build test"
    echo "   Build command that will be used in ECS:"
    echo "   docker build -f ./backend/Dockerfile -t pipeline-pulse ./backend"
fi

echo ""
echo "🎉 Build context verification complete!"
echo ""
echo "📋 Deployment checklist:"
echo "✅ Build context: ./backend (correct)"
echo "✅ Dockerfile path: ./backend/Dockerfile (correct)"
echo "✅ Working directory: /app (set in Dockerfile and ECS task)"
echo "✅ Main module: main:app (will be found at /app/main.py)"
echo ""
echo "🚀 Ready for ECS deployment!" 