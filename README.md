 Horizon RealEstate360


A production-grade, full-stack Property Management & Real Estate Operations platform built with Java Spring Boot Microservices and a React 18 SPA.




📌 Project Description

Horizon RealEstate360 is an enterprise-level property management system designed to handle end-to-end real estate operations — from property listings and lease management to billing, maintenance, compliance, and tenant self-service. The platform is built on a Microservices Architecture with 10 independently deployable backend services, a unified API Gateway, Eureka service discovery, and a modern React frontend — all containerized with Docker Compose for one-command local deployment.

Built during my internship at Cognizant (Feb 2026 – Jun 2026) as a Java Full Stack Developer.


🛠️ Tech Stack

Backend

LayerTechnologyFrameworkJava Spring BootMicroservicesSpring Cloud (Eureka, API Gateway)SecuritySpring Security, JWT, RBAC, bcryptORMSpring Data JPA, HibernateDatabaseMySQL 8.0MigrationsFlywayContainerizationDocker, Docker ComposeAPI DocsOpenAPI / Swagger

Frontend

LayerTechnologyFrameworkReact 18State ManagementRedux Toolkit (RTK Query)RoutingReact Router v6FormsReact Hook Form + ZodUIReact BootstrapBuild ToolVite

Testing

TypeToolsBackend Unit & IntegrationJUnit 5, MockitoFrontend UnitVitest, React Testing Library, MSW


📦 Microservices Breakdown

ServicePortResponsibilityAPI Gateway9090Single entry point, JWT filter, load balancingDiscovery (Eureka)8761Service registry for all microservicesIAM Service8082User auth, JWT minting, roles, RBACProperty Service8081Properties, units, amenities, media, availabilityLeasing Service8083Listings, applications, leases, lease workflowsTenant Service8084Tenant profiles, documents, service requestsMaintenance Service8085Work orders, vendors, part inventory, schedulesCompliance Service8086Audit logs, compliance reports, retention policiesBilling Service8087Invoices, receipts, ledger, deposits, adjustmentsAsset Service8088Asset tracking, maintenance plans, space utilizationReporting Service8089KPI reports, datasets, scheduled report jobsNotification Service8090Alert rules, escalation scheduler, in-app & email


✨ Key Features


🔐 JWT Authentication & RBAC — IAM service mints tokens; Gateway validates on every request; role-gated UI and API endpoints
🏠 Property & Unit Management — Full CRUD for properties, units, amenities, floor plans, photos, and availability calendar
📋 Leasing Workflow — End-to-end leasing: listings → applications → screening → lease creation → renewal → termination
👤 Tenant Portal — Self-service portal for tenants to browse listings, submit applications, track payments, raise maintenance requests
🔧 Maintenance Management — Work order lifecycle (create → assign → schedule → complete → close), vendor management, part inventory
💰 Billing & Accounting — Invoice generation, receipts, ledger entries, deposits, charge adjustments, arrears tracking
📊 Reporting & Analytics — KPI reports, analytics datasets, scheduled export jobs
🔔 Notification Service — Configurable alert rules, escalation engine, multi-channel dispatch (in-app + email simulation)
🛡️ Compliance — Append-only audit logs, compliance reports, data retention policies
🐳 Fully Containerized — All 12 services + MySQL in a single docker-compose.yml



🗄️ Database Design


51 tables across 10 bounded contexts in a single MySQL database (split-ready per service)
BIGINT UNSIGNED PKs + CHAR(36) UUIDs for all public identifiers
DECIMAL(19,4) for all monetary columns
DATETIME UTC timestamps with created_at / updated_at on every transactional table
Cross-context references store IDs without FK constraints — ready to split into per-service databases with zero refactoring
Flyway versioned migrations per service
Optimistic locking and soft deletes via status enums.
