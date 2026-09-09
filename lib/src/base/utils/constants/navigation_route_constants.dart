// Auth Screen Routes
const String routeLogin = "routeLogin";
const String routeSignUp = "routeSignUp";

// QA Control Center — legacy single-project routes (kept for backward compat)
const String routeQAHome = "routeQAHome";
const String routeQASetup = "routeQASetup";

// QA Control Center — multi-project routes
const String routeProjects = "routeProjects";           // landing: all projects
const String routeProjectDetail = "routeProjectDetail"; // run a project's surfaces
const String routeCreateProject = "routeCreateProject"; // create new project
const String routeEditProject = "routeEditProject";     // edit existing project
const String routeCommandLibrary = "routeCommandLibrary"; // whole-project command pool
const String routeCommandEdit = "routeCommandEdit";       // edit one command
const String routeSurfaceCommandManager = "routeSurfaceCommandManager"; // one surface + one stage
const String routeScripts = "routeScripts";               // CRUD scripts for a surface
const String routeReports = "routeReports";               // archived reports for a surface
const String routeRecentRuns = "routeRecentRuns";         // global run history across all projects
const String routeActiveRuns = "routeActiveRuns";         // live/recent run progress (global)
const String routeDevices = "routeDevices";               // global device management
