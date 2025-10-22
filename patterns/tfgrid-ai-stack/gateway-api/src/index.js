#!/usr/bin/env node

/**
 * TFGrid AI Stack - Gateway Route Management API
 * Version: 0.12.0-dev (MVP)
 * 
 * Manages nginx routes dynamically for deployed projects
 */

const express = require('express');
const bodyParser = require('body-parser');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs').promises;
const { exec } = require('child_process');
const util = require('util');
const execAsync = util.promisify(exec);

const app = express();
const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY || 'dev-api-key';

// Middleware
app.use(bodyParser.json());

// Simple logging
const log = (level, message, data = {}) => {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    message,
    ...data
  }));
};

// Authentication middleware
const authenticate = (req, res, next) => {
  const authHeader = req.headers.authorization;
  
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid authorization header' });
  }
  
  const token = authHeader.slice(7);
  
  if (token !== API_KEY) {
    return res.status(401).json({ error: 'Invalid API key' });
  }
  
  next();
};

// In-memory route storage (MVP - would be database in production)
const routes = new Map();

// Helper functions
async function generateNginxConfig(route) {
  return `
# Route: ${route.id}
# Path: ${route.path}
# Created: ${route.created_at}

location ${route.path} {
    alias ${route.backend};
    index index.html index.htm;
    try_files $uri $uri/ =404;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
}
`;
}

async function testNginxConfig() {
  try {
    await execAsync('nginx -t');
    return { valid: true };
  } catch (error) {
    return { valid: false, error: error.message };
  }
}

async function reloadNginx() {
  try {
    await execAsync('systemctl reload nginx');
    log('info', 'Nginx reloaded successfully');
    return true;
  } catch (error) {
    log('error', 'Failed to reload nginx', { error: error.message });
    return false;
  }
}

async function writeRouteConfig(routeId, config) {
  const configPath = `/etc/nginx/sites-available/route-${routeId}.conf`;
  await fs.writeFile(configPath, config);
  
  const enabledPath = `/etc/nginx/sites-enabled/route-${routeId}.conf`;
  try {
    await fs.symlink(configPath, enabledPath);
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
  }
}

async function deleteRouteConfig(routeId) {
  const configPath = `/etc/nginx/sites-available/route-${routeId}.conf`;
  const enabledPath = `/etc/nginx/sites-enabled/route-${routeId}.conf`;
  
  try {
    await fs.unlink(enabledPath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  
  try {
    await fs.unlink(configPath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

// API Routes

/**
 * Health check endpoint
 * GET /api/v1/health
 */
app.get('/api/v1/health', async (req, res) => {
  const uptime = process.uptime();
  const nginxTest = await testNginxConfig();
  
  res.json({
    status: nginxTest.valid ? 'healthy' : 'degraded',
    uptime: Math.floor(uptime),
    routes: routes.size,
    nginx: nginxTest.valid ? 'running' : 'error',
    timestamp: new Date().toISOString()
  });
});

/**
 * Create a new route
 * POST /api/v1/routes
 */
app.post('/api/v1/routes', authenticate, async (req, res) => {
  try {
    const { path, backend } = req.body;
    
    // Validate input
    if (!path || !backend) {
      return res.status(400).json({ 
        error: 'Missing required fields',
        required: ['path', 'backend']
      });
    }
    
    // Validate path format
    if (!path.startsWith('/') || path.includes('..')) {
      return res.status(400).json({ 
        error: 'Invalid path format',
        details: 'Path must start with / and not contain ..'
      });
    }
    
    // Check for existing route
    for (const [id, route] of routes.entries()) {
      if (route.path === path) {
        return res.status(409).json({ 
          error: 'Route already exists',
          existing_id: id
        });
      }
    }
    
    // Create route
    const routeId = uuidv4();
    const route = {
      id: routeId,
      path,
      backend,
      status: 'active',
      created_at: new Date().toISOString()
    };
    
    // Generate nginx config
    const nginxConfig = await generateNginxConfig(route);
    
    // Test config
    await writeRouteConfig(routeId, nginxConfig);
    const testResult = await testNginxConfig();
    
    if (!testResult.valid) {
      // Rollback
      await deleteRouteConfig(routeId);
      return res.status(400).json({ 
        error: 'Invalid nginx configuration',
        details: testResult.error
      });
    }
    
    // Reload nginx
    const reloaded = await reloadNginx();
    if (!reloaded) {
      // Rollback
      await deleteRouteConfig(routeId);
      return res.status(500).json({ 
        error: 'Failed to reload nginx'
      });
    }
    
    // Save route
    routes.set(routeId, route);
    
    log('info', 'Route created', { route_id: routeId, path });
    
    res.status(201).json({
      id: routeId,
      path,
      status: 'active'
    });
    
  } catch (error) {
    log('error', 'Failed to create route', { error: error.message });
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * List all routes
 * GET /api/v1/routes
 */
app.get('/api/v1/routes', authenticate, async (req, res) => {
  const routeList = Array.from(routes.values());
  res.json(routeList);
});

/**
 * Get route by ID
 * GET /api/v1/routes/:id
 */
app.get('/api/v1/routes/:id', authenticate, async (req, res) => {
  const { id } = req.params;
  const route = routes.get(id);
  
  if (!route) {
    return res.status(404).json({ error: 'Route not found' });
  }
  
  res.json(route);
});

/**
 * Delete a route
 * DELETE /api/v1/routes/:id
 */
app.delete('/api/v1/routes/:id', authenticate, async (req, res) => {
  try {
    const { id } = req.params;
    
    const route = routes.get(id);
    if (!route) {
      return res.status(404).json({ error: 'Route not found' });
    }
    
    // Delete nginx config
    await deleteRouteConfig(id);
    
    // Test and reload
    const testResult = await testNginxConfig();
    if (!testResult.valid) {
      return res.status(500).json({ 
        error: 'Nginx configuration invalid after deletion'
      });
    }
    
    await reloadNginx();
    
    // Remove from storage
    routes.delete(id);
    
    log('info', 'Route deleted', { route_id: id, path: route.path });
    
    res.status(204).send();
    
  } catch (error) {
    log('error', 'Failed to delete route', { error: error.message });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Error handling
app.use((err, req, res, next) => {
  log('error', 'Unhandled error', { error: err.message, stack: err.stack });
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
app.listen(PORT, () => {
  log('info', 'Gateway API started', { 
    port: PORT,
    api_version: 'v1',
    auth: 'enabled'
  });
  console.log(`
╔════════════════════════════════════════════════════════════╗
║     TFGrid Gateway API - Running                           ║
╚════════════════════════════════════════════════════════════╝

Port: ${PORT}
Health Check: http://localhost:${PORT}/api/v1/health
Authentication: Bearer token required

API Endpoints:
  POST   /api/v1/routes      Create route
  GET    /api/v1/routes      List routes
  GET    /api/v1/routes/:id  Get route
  DELETE /api/v1/routes/:id  Delete route
  GET    /api/v1/health      Health check

Ready to accept requests...
`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  log('info', 'SIGTERM received, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  log('info', 'SIGINT received, shutting down gracefully');
  process.exit(0);
});

module.exports = app;