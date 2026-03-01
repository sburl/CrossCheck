# Claude Code Custom Agents

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-09-16-00

This directory contains custom agents for Claude Code, curated for high-value specialized tasks.

---

## 📦 Agent Inventory (14 total)

### Engineering (5)
- **backend-architect** - Backend architecture and database design
- **devops-automator** - CI/CD pipelines, infrastructure, and deployment
- **frontend-developer** - Frontend development and UI implementation
- **rapid-prototyper** - Fast MVP/prototype building within 6-day cycles
- **test-writer-fixer** - Test automation, writing, and fixing

### Design (2)
- **ui-designer** - Interface design and component creation
- **whimsy-injector** - UX delight patterns and playful moments

### Product (1)
- **sprint-prioritizer** - Sprint planning and task prioritization

### Project Management (1)
- **project-shipper** - Shipping features and project coordination

### Testing (2)
- **api-tester** - API testing and validation
- **tool-evaluator** - Tech stack evaluation and tool selection

### Bonus (3)
- **studio-coach** - Performance coaching and guidance
- **coach** - Strategic planning, motivation, and agent coordination
- **claude_critic** - Critical analysis and risk identification

---

## 📚 Attribution

These agents are adapted from **[Claude Code Studio](https://github.com/arnaldo-delisio/claude-code-studio)** by Arnaldo Delisio, an excellent open-source repository that transforms Claude Code into a complete development studio with 40+ specialized AI agents.

**Original Repository:** https://github.com/arnaldo-delisio/claude-code-studio
**License:** MIT License
**Author:** Arnaldo Delisio (@arnaldo-delisio)
**Credit:** Thank you to Arnaldo Delisio for creating and open-sourcing this comprehensive agent collection

**Modifications:**
- Curated to 14 agents (from original 39) based on unique value
- Removed agents redundant with Anthropic's built-in general-purpose agent
- Kept only agents with specialized domain expertise

---

## 🚀 Installation

### On New Computer

1. **Copy agents to Claude Code directory:**
   ```bash
   cp -r ~/Documents/Developer/CrossCheck/agents/* ~/.claude/agents/
   ```

2. **Verify installation:**
   ```bash
   find ~/.claude/agents -name "*.md" -not -path "*/plugins/*"
   ```

   Should show 14 agent files.

3. **Restart Claude Code** (if running)

### Enforce This Agent List (Clean Install)

To remove all other agents and enforce only these 14:

```bash
# Backup existing agents
cp -r ~/.claude/agents ~/.claude/agents-backup-$(date +%Y%m%d)

# Remove all custom agents (keeps plugins)
rm -rf ~/.claude/agents/engineering
rm -rf ~/.claude/agents/design
rm -rf ~/.claude/agents/testing
rm -rf ~/.claude/agents/bonus
rm -rf ~/.claude/agents/marketing
rm -rf ~/.claude/agents/product
rm -rf ~/.claude/agents/studio-operations
rm -f ~/.claude/agents/*.md

# Install our curated 14
cp -r ~/Documents/Developer/CrossCheck/agents/* ~/.claude/agents/
```

---

## 🎯 Usage

Agents are invoked via the `Task` tool with `subagent_type` parameter:

### Example: Rapid Prototyping
```
User: "Build a TikTok-style video feed prototype"
Claude: Uses Task(rapid-prototyper)
```

### Example: Test Writing
```
User: "Write tests for the auth system"
Claude: Uses Task(test-writer-fixer)
```

### Example: UI Design
```
User: "Design a modern login screen"
Claude: Uses Task(ui-designer)
```

### Example: Strategic Planning
```
User: "We need to plan our next sprint"
Claude: Uses Task(coach)
```

---

## 🔍 Why These 14?

**Kept agents with unique specialized expertise that Anthropic's built-in agents don't provide:**

| Agent | Why Kept | Alternative |
|-------|----------|-------------|
| **backend-architect** | Backend system design expertise | General-purpose can code, but lacks architectural focus |
| **devops-automator** | Infrastructure and CI/CD expertise | General-purpose can script, but lacks DevOps patterns |
| **frontend-developer** | Modern frontend framework expertise | General-purpose can code UI, but lacks framework depth |
| **rapid-prototyper** | 6-day sprint patterns, MVP expertise | General-purpose can code, but lacks rapid iteration focus |
| **test-writer-fixer** | Test-first development patterns | General-purpose can test, but lacks TDD workflow |
| **ui-designer** | Design systems, component patterns | General-purpose can code UI, but lacks design expertise |
| **whimsy-injector** | UX delight, playful moments | No general-purpose equivalent |
| **sprint-prioritizer** | Task breakdown and prioritization | General-purpose lacks product management focus |
| **project-shipper** | Release management and shipping | General-purpose lacks delivery focus |
| **api-tester** | API validation patterns | General-purpose can test, but lacks API depth |
| **tool-evaluator** | Tech stack decisions, tool comparison | No general-purpose equivalent |
| **studio-coach** | Performance coaching | No general-purpose equivalent |
| **coach** | Strategic planning, agent coordination | No general-purpose equivalent |
| **claude_critic** | Critical analysis, risk identification | No general-purpose equivalent |

**Removed 25 agents that were redundant with Anthropic's general-purpose agent:**
- Engineering agents (backend, frontend, DevOps, AI, mobile)
- Marketing agents (TikTok, Instagram, Reddit, Twitter, growth)
- Product agents (trend research, feedback, sprint planning)
- Operations agents (finance, legal, analytics, support)
- Design agents (brand, visual storytelling, UX research)
- Testing agents (API, performance, workflow optimization)
- Project management agents (experiment tracking, shipping, production)

---

## 📖 Agent Descriptions

### backend-architect
Backend system design and API architecture. Specializes in:
- Database schema design
- API endpoint planning
- System architecture
- Performance optimization

### devops-automator
Infrastructure and deployment automation. Specializes in:
- CI/CD pipelines
- Infrastructure as Code
- Deployment scripts
- Environment configuration

### frontend-developer
Modern frontend framework implementation. Specializes in:
- React/Vue/Svelte development
- State management
- Client-side routing
- Responsive implementation

### rapid-prototyper
Fast MVP and prototype development within 6-day development cycles. Specializes in:
- Scaffolding new projects quickly
- Building functional demos
- Integrating trending features
- Creating testable prototypes

### test-writer-fixer
Comprehensive test automation and fixing. Specializes in:
- Writing tests alongside code (not after)
- Fixing failing tests
- Test-driven development patterns
- Ensuring code coverage

### ui-designer
Interface design and component creation. Specializes in:
- Creating beautiful, functional UIs
- Design systems
- Component libraries
- Visual aesthetics

### whimsy-injector
UX delight and playful moments. Specializes in:
- Adding joy and surprise to interfaces
- Playful error messages
- Delightful loading states
- Shareable moments

### sprint-prioritizer
Task breakdown and sprint planning. Specializes in:
- Breaking down features into tasks
- Estimating effort
- Prioritizing backlogs
- Sprint organization

### project-shipper
Release management and feature delivery. Specializes in:
- Release checklists
- Deployment coordination
- Launch preparation
- Post-launch monitoring

### api-tester
API validation and contract testing. Specializes in:
- Endpoint testing
- Data validation
- Error handling verification
- Integration tests

### tool-evaluator
Tech stack evaluation and tool selection. Specializes in:
- Comparing frameworks and tools
- Rapid tool assessment
- Making recommendations for 6-day cycles
- Cost/benefit analysis

### studio-coach
Performance coaching and guidance. Specializes in:
- Agent performance improvement
- Workflow optimization
- Best practices
- Continuous learning

### coach
Strategic planning and agent coordination. Specializes in:
- Performance coaching for agents
- Multi-agent coordination
- Strategic planning
- Team motivation

### claude_critic
Critical analysis without bias. Specializes in:
- Identifying risks and blind spots
- Alternative approaches
- Challenging assumptions
- Devil's advocate perspective

---

## 🔄 Updates

To update agents when the CrossCheck repo changes:

```bash
# Pull latest from repo
cd ~/Documents/Developer/CrossCheck
git pull

# Copy updated agents
cp -r agents/* ~/.claude/agents/
```

---

## 📝 Related Documentation

- **CLAUDE.md** - Main workflow and agent usage patterns
- **skill-sources/INSTALL.md** - Installing skills

---

## 🙏 Thanks

Huge thanks to Arnaldo Delisio for creating and open-sourcing this excellent collection of agents. Their work made rapid product development with Claude Code significantly more powerful.

**Check out their work:** https://github.com/arnaldo-delisio/claude-code-studio
