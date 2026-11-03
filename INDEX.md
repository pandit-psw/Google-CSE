# Google Workspace CSE Self-Hosted Key Service - Documentation Index

## 🚀 Start Here

New to this project? Follow this path:

1. **[SUMMARY.md](./SUMMARY.md)** - Overview and what this project does (5 min read)
2. **[QUICKSTART.md](./QUICKSTART.md)** - Test locally in 5 minutes
3. **[DEPLOYMENT.md](./DEPLOYMENT.md)** - Deploy to production (1-2 hours)

## 📚 Documentation

### Essential Guides

| Document | Purpose | When to Read |
|----------|---------|--------------|
| [SUMMARY.md](./SUMMARY.md) | High-level overview, features, benefits | First time here |
| [QUICKSTART.md](./QUICKSTART.md) | Local testing setup | Before deploying |
| [DEPLOYMENT.md](./DEPLOYMENT.md) | Production deployment steps | Ready to deploy |
| [README.md](./README.md) | Technical architecture overview | Understanding the system |

### Deep Dives

| Document | Purpose | When to Read |
|----------|---------|--------------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Detailed technical architecture, data flow, security model | Want deep understanding |
| [COSTS.md](./COSTS.md) | Cost analysis, resource requirements, scalability | Planning deployment |
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Common issues and solutions | Something's not working |

## 💻 Code Files

### Source Code

| File | Purpose | Lines |
|------|---------|-------|
| [src/server.js](./src/server.js) | Main Express server, KACLS endpoints | ~350 |
| [src/crypto.js](./src/crypto.js) | AES-KW key wrapping/unwrapping | ~70 |
| [src/database.js](./src/database.js) | SQLite database for KEKs and audit logs | ~180 |
| [src/auth.js](./src/auth.js) | Google Workspace authentication | ~180 |

### Configuration & Scripts

| File | Purpose |
|------|---------|
| [package.json](./package.json) | Node.js dependencies and scripts |
| [.env.example](./.env.example) | Environment variables template |
| [.gitignore](./.gitignore) | Git ignore rules |
| [setup-local.sh](./setup-local.sh) | Automated local setup script |
| [test.js](./test.js) | Comprehensive test suite |

## 🎯 Quick Navigation

### I want to...

**...understand what this is**
→ Read [SUMMARY.md](./SUMMARY.md)

**...test it locally**
→ Follow [QUICKSTART.md](./QUICKSTART.md)

**...deploy to production**
→ Follow [DEPLOYMENT.md](./DEPLOYMENT.md)

**...understand the architecture**
→ Read [ARCHITECTURE.md](./ARCHITECTURE.md)

**...know the costs**
→ Read [COSTS.md](./COSTS.md)

**...fix an issue**
→ Check [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

**...understand the code**
→ Start with [src/server.js](./src/server.js), then [src/crypto.js](./src/crypto.js)

**...see a diagram**
→ [ARCHITECTURE.md](./ARCHITECTURE.md) has detailed diagrams

**...know if it will work for me**
→ [COSTS.md](./COSTS.md) - "Real-World Usage Scenarios" section

## 📖 Reading Order by Audience

### For Decision Makers
1. [SUMMARY.md](./SUMMARY.md) - What and why
2. [COSTS.md](./COSTS.md) - Cost analysis
3. [ARCHITECTURE.md](./ARCHITECTURE.md) - Security model section

### For System Administrators
1. [QUICKSTART.md](./QUICKSTART.md) - Local test
2. [DEPLOYMENT.md](./DEPLOYMENT.md) - Production deployment
3. [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Operations

### For Developers
1. [README.md](./README.md) - Technical overview
2. [ARCHITECTURE.md](./ARCHITECTURE.md) - Detailed architecture
3. [src/server.js](./src/server.js) - Code walkthrough
4. [test.js](./test.js) - Test examples

### For Security Reviewers
1. [ARCHITECTURE.md](./ARCHITECTURE.md) - Security model and threat analysis
2. [src/crypto.js](./src/crypto.js) - Cryptographic implementation
3. [src/auth.js](./src/auth.js) - Authentication logic
4. [DEPLOYMENT.md](./DEPLOYMENT.md) - Security hardening section

## 🔍 Key Sections by Topic

### Security
- **Cryptographic algorithms:** [ARCHITECTURE.md](./ARCHITECTURE.md#technical-specifications)
- **Security model:** [ARCHITECTURE.md](./ARCHITECTURE.md#security-model)
- **Threat model:** [ARCHITECTURE.md](./ARCHITECTURE.md#threat-model)
- **Hardening checklist:** [ARCHITECTURE.md](./ARCHITECTURE.md#security-hardening-checklist)
- **Authentication:** [src/auth.js](./src/auth.js)

### Performance
- **Benchmarks:** [COSTS.md](./COSTS.md#performance-benchmarks)
- **Scalability:** [COSTS.md](./COSTS.md#real-world-usage-scenarios)
- **Resource usage:** [COSTS.md](./COSTS.md#oracle-always-free-tier-specifications)

### Operations
- **Deployment steps:** [DEPLOYMENT.md](./DEPLOYMENT.md)
- **Monitoring:** [TROUBLESHOOTING.md](./TROUBLESHOOTING.md#monitoring)
- **Backup:** [DEPLOYMENT.md](./DEPLOYMENT.md#backup)
- **Troubleshooting:** [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

### Development
- **API specification:** [ARCHITECTURE.md](./ARCHITECTURE.md#api-specifications)
- **Database schema:** [ARCHITECTURE.md](./ARCHITECTURE.md#database-schema)
- **Data flow:** [ARCHITECTURE.md](./ARCHITECTURE.md#data-flow)
- **Testing:** [test.js](./test.js) and [TROUBLESHOOTING.md](./TROUBLESHOOTING.md#testing)

## 📊 Document Statistics

| Document | Words | Reading Time |
|----------|-------|--------------|
| SUMMARY.md | ~2,500 | 10 min |
| QUICKSTART.md | ~1,800 | 7 min |
| DEPLOYMENT.md | ~2,800 | 12 min |
| ARCHITECTURE.md | ~4,500 | 18 min |
| COSTS.md | ~3,500 | 14 min |
| TROUBLESHOOTING.md | ~3,000 | 12 min |
| **Total** | **~18,000** | **~75 min** |

## 🎓 Learning Path

### Level 1: Overview (15 minutes)
- Read [SUMMARY.md](./SUMMARY.md)
- Skim [QUICKSTART.md](./QUICKSTART.md)
- **Goal:** Understand what this is and if it's for you

### Level 2: Hands-On (1 hour)
- Follow [QUICKSTART.md](./QUICKSTART.md) - actually do it
- Run [test.js](./test.js)
- Explore [src/server.js](./src/server.js)
- **Goal:** See it working locally

### Level 3: Deployment (2-3 hours)
- Read [DEPLOYMENT.md](./DEPLOYMENT.md) fully
- Set up Oracle Cloud
- Set up Google Cloud
- Deploy and test
- **Goal:** Production-ready service

### Level 4: Expert (4-6 hours)
- Read all documentation
- Review all source code
- Understand [ARCHITECTURE.md](./ARCHITECTURE.md) deeply
- Complete [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) scenarios
- **Goal:** Full system mastery

## 🔧 Common Tasks

### Local Testing
```bash
# Read: QUICKSTART.md
./setup-local.sh
npm start
```

### Production Deployment
```bash
# Read: DEPLOYMENT.md
# Follow step by step
```

### Troubleshooting
```bash
# Read: TROUBLESHOOTING.md
sudo journalctl -u cse-key-service -f
curl http://localhost:3000/healthz
```

### Updating Code
```bash
cd /opt/cse-key-service/app
git pull  # if using git
sudo systemctl restart cse-key-service
```

### Viewing Logs
```bash
# Application
sudo journalctl -u cse-key-service -n 100

# Audit logs
curl http://localhost:3000/v1/audit/logs?limit=50

# nginx
sudo tail -f /var/log/nginx/access.log
```

## 📞 Support Resources

### Official Documentation
- Google Workspace CSE: https://developers.google.com/workspace/cse
- Oracle Cloud Free Tier: https://www.oracle.com/cloud/free/
- Node.js: https://nodejs.org/
- Express: https://expressjs.com/

### Helpful Tools
- SSL Test: https://www.ssllabs.com/ssltest/
- DNS Check: https://dnschecker.org/
- JSON Formatter: https://jsonformatter.org/

## 🤝 Contributing

Areas for improvement:
- [ ] Docker/Kubernetes deployment
- [ ] Terraform/IaC automation
- [ ] Prometheus metrics exporter
- [ ] Web UI for management
- [ ] Multi-KEK support with policies
- [ ] Advanced key rotation
- [ ] Additional authentication providers

## 📋 Checklist for Success

### Before Starting
- [ ] Read [SUMMARY.md](./SUMMARY.md)
- [ ] Verify Google Workspace edition supports CSE
- [ ] Have domain name ready (~$12/year)
- [ ] Basic Linux knowledge

### Local Testing
- [ ] Follow [QUICKSTART.md](./QUICKSTART.md)
- [ ] Run [test.js](./test.js) successfully
- [ ] Test wrap/unwrap operations

### Production Deployment
- [ ] Oracle Cloud account created
- [ ] Google Cloud project set up
- [ ] Domain DNS configured
- [ ] Follow [DEPLOYMENT.md](./DEPLOYMENT.md) completely
- [ ] SSL certificate obtained
- [ ] Firewall configured
- [ ] Service starts successfully
- [ ] Health check responds externally

### Post-Deployment
- [ ] Backup Master KEK securely offline
- [ ] Configure monitoring
- [ ] Set up backup schedule
- [ ] Register service in Google Workspace
- [ ] Test with actual Google Docs
- [ ] Review [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

### Security
- [ ] Review [ARCHITECTURE.md](./ARCHITECTURE.md) security section
- [ ] Complete security hardening checklist
- [ ] Restrict SSH access
- [ ] Enable audit logging
- [ ] Regular security updates scheduled

## 🎉 You're Ready!

Start with [SUMMARY.md](./SUMMARY.md) if you haven't already, then follow [QUICKSTART.md](./QUICKSTART.md) to test locally.

Questions? Check [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) first!

Good luck! 🚀
