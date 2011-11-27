package vark

uses java.io.File
uses java.lang.System
uses java.lang.Class
uses java.util.Iterator
uses gw.util.Shell
uses gw.util.Pair
uses gw.vark.Aardvark
uses gw.vark.annotations.*
uses gw.vark.antlibs.*

enhancement RoninVarkTargets : gw.vark.AardvarkFile {

  property get RoninAppName() : String {
    return this.file(".").ParentFile.Name
  }

  property get GosuFiles() : File {
    var gosuHome = System.getenv()["GOSU_HOME"] as String
    if(gosuHome != null) {
      return new File(gosuHome, "jars")
    } else {
      this.logWarn("\n  Warning: GOSU_HOME is not defined, using the Gosu distribution bundled with Aardvark." +
                    "\n  Ideally, you should define the GOSU_HOME environment variable.\n")
      return new File(new File(gw.vark.Aardvark.Type.BackingClass.ProtectionDomain.CodeSource.Location.Path).ParentFile, "gosu")
    }
  }

  property set EDGE_RONIN_REPO( str : String ) {
    System.setProperty( "EDGE_RONIN_REPO", str )
  }

  property get EDGE_RONIN_REPO() : String {
    return System.getProperty( "EDGE_RONIN_REPO" )
  }

  property set EDGE_TOSA_REPO( str : String ) {
    System.setProperty( "EDGE_TOSA_REPO", str )
  }

  property get EDGE_TOSA_REPO() : String {
    return System.getProperty( "EDGE_TOSA_REPO" )
  }

  property get EdgeDir() : File {
    return this.file("edge")
  }

  property get RoninEdgeDir() : File {
    return EdgeDir.file("ronin")
  }

  property get TosaEdgeDir() : File {
    return EdgeDir.file("tosa")
  }

  /* Installs Edge Ronin from Github and compiles it */
  @Target
  function installEdgeRonin() {
    EdgeDir.mkdir()
    print( Shell.exec( "git clone " + EDGE_RONIN_REPO + " " + RoninEdgeDir.AbsolutePath  ) )
    print( Shell.exec( "git clone " + EDGE_TOSA_REPO + " " + TosaEdgeDir.AbsolutePath ) )
    compileEdgeRonin()    
  }

  /* Updates Edge Ronin from Github and compiles it */
  @Target
  function updateEdgeRonin() {
    print( Shell.exec( "git --git-dir=" + RoninEdgeDir.AbsolutePath + "/.git pull"  ) )
    print( Shell.exec( "git --git-dir=" + TosaEdgeDir.AbsolutePath + "/.git pull" ) )
    compileEdgeRonin()
  }

  /* Compiles Edge Ronin */
  @Target
  function compileEdgeRonin() {
    print("compiling ronin")
    print( Shell.exec( "vark -f " + roninEdgeDir.AbsolutePath + "/build.vark build" ) )
    print("compiling tosa")
    print( Shell.exec( "vark -f " + tosaEdgeDir.AbsolutePath + "/build.vark build" ) )
    print("installing ronin")
    TosaEdgeDir.file( "tosa/build/tosa.jar" ).copyTo( this.file("lib").Children.firstWhere( \ f -> f.Name.startsWith( "tosa-" )  ) )
    RoninEdgeDir.file( "ronin/build/ronin.jar" ).copyTo( this.file("lib").Children.firstWhere( \ f -> f.Name.startsWith( "ronin-" )  ) )
    RoninEdgeDir.file( "roninit/build/roninit.jar" ).copyTo( this.file("support").Children.firstWhere( \ f -> f.Name.startsWith( "roninit-" )  ) )
    RoninEdgeDir.file( "roninlog/build/roninlog.jar" ).copyTo( this.file("support").Children.firstWhere( \ f -> f.Name.startsWith( "roninlog-" )  ) )
    RoninEdgeDir.file( "ronintest/build/ronintest.jar" ).copyTo( this.file("support").Children.firstWhere( \ f -> f.Name.startsWith( "ronintest-" )  ) )
  }

  /* Uninstalls Edge Ronin */
  @Target
  function uninstallEdgeRonin() {
    this.file( "lib").Children.where( \ f -> f.Name.startsWith( "ronin" )  ).each( \ f -> f.delete()  )
    this.file( "lib").Children.where( \ f -> f.Name.startsWith( "tosa" )  ).each( \ f -> f.delete()  )
    this.file( "support").Children.where( \ f -> f.Name.startsWith( "ronin" )  ).each( \ f -> f.delete()  )
    deps()
    EdgeDir.deleteRecursively()
  }

  /* Retrieves dependencies as configured in ivy.xml */
  @Target
  function deps() {
    Ivy.configure(:file = this.file("ivy-settings.xml"))
    Ivy.retrieve(:pattern = "[conf]/[artifact]-[revision](-[classifier]).[ext]", :log = "download-only")
  }

  /* Compiles any Java classes */
  @Target
  function compile() {
    var classesDir = this.file("classes")
    classesDir.mkdirs()
    Ant.javac( :srcdir = this.path(this.file("src")),
               :destdir = classesDir,
               :classpath = this.classpath(this.file("src").fileset())
                 .withFileset(this.file("lib").fileset())
                 .withFileset(GosuFiles.fileset()),
               :debug = true,
               :includeantruntime = false)
  }

  /* Starts up a Ronin environment with a working H2 database */
  @Target
  @Depends({"deps", "compile"})
  @Param("waitForDebugger", "Suspend the server until a debugger connects.")
  @Param("port", "The port to start the server on (default is 8080).")
  @Param("dontStartDB", "Suppress starting the H2 web server.")
  @Param("env", "A comma-separated list of environment variables, formatted as \"ronin.name=value\".")
  function server(waitForDebugger : boolean, dontStartDB : boolean, port : int = 8080, env : String = "") {
    var cp = this.classpath(this.file("support").fileset())
               .withFileset(this.file("lib").fileset())
               .withFileset(GosuFiles.fileset())
    Ant.java(:classpath=cp,
                   :jvmargs=getJvmArgsString(waitForDebugger) + " " + env.split(",").map(\e -> "-D" + e).join(" "),
                   :classname="ronin.DevServer",
                   :fork=true,
                   :failonerror=true,
                   :args="server${dontStartDB ? "-nodb" : ""} ${port} " + this.file(".").AbsolutePath)
  }

  /* Clears and reinitializes the database */
  @Target
  @Depends({"deps"})
  @Param("waitForDebugger", "Suspend the server until a debugger connects.")
  function resetDb(waitForDebugger : boolean) {
    var cp = this.classpath(this.file("support").fileset())
               .withFileset(this.file("lib").fileset())
               .withFileset(GosuFiles.fileset())
    Ant.java(:classpath=cp,
                   :jvmargs=getJvmArgsString(waitForDebugger),
                   :classname="ronin.DevServer",
                   :fork=true,
                   :failonerror=true,
                   :args="upgrade_db " + this.file(".").AbsolutePath)
  }

  /* Verifies your application code */
  @Target
  @Depends({"deps", "compile"})
  @Param("waitForDebugger", "Suspend the server until a debugger connects.")
  @Param("env", "A comma-separated list of environment variables, formatted as \"ronin.name=value\".")
  function verifyApp(waitForDebugger : boolean, env : String = "") {

    var cp = this.classpath(this.file("support").fileset())
               .withFileset(this.file("lib").fileset())
               .withFile(this.file("src"))
               .withFileset(GosuFiles.fileset())

    Ant.java(:classpath=cp,
                   :classname="ronin.DevServer",
                   :jvmargs=getJvmArgsString(waitForDebugger) + " -Xmx256m -XX:MaxPermSize=128m " + env.split(",").map(\e -> "-D" + e).join(" "),
                   :fork=true,
                   :failonerror=true,
                   :args="verify_ronin_app ${this.file(".").AbsolutePath}")
  }

  /* Verifies your application code under all possible combinations of environment properties */
  @Target
  @Depends({"deps", "compile"})
  @Param("waitForDebugger", "Suspend the server until a debugger connects.")
  function verifyAll(waitForDebugger : boolean) {
    doForAllEnvironments(\env -> verifyApp(waitForDebugger, env), "Verifying", "Verified")
  }

  /* Deletes the build directory */
  @Target
  function clean() {
    if(this.file("build").exists()) {
      this.file("build").deleteRecursively()
    }
    if(this.file("classes").exists()) {
      this.file("classes").deleteRecursively()
    }
    if(this.file("lib").exists()) {
      Ant.delete(:filesetList = {this.file("lib").fileset()})
    }
    if(this.file("support").exists()) {
      Ant.delete(:filesetList = {this.file("support").fileset(:excludes="vark/*")})
    }
  }

  /* creates a war from the current ronin project */
  @Target
  @Depends({"deps", "compile"})
  function makeWar() {

    // copy over the html stuff
    var warDir = this.file("build/war")
    warDir.mkdirs()
    Ant.copy(:filesetList = { this.file("html").fileset() },
              :todir = warDir)

    // copy in the classes
    var webInfDir = this.file("build/war/WEB-INF")
    var classesDir = webInfDir.file("classes")
    classesDir.mkdirs()
    Ant.copy(:filesetList = { this.file("src").fileset(:excludes = "**/*.java") },
              :todir = classesDir)
    if(this.file("classes").exists()) {
      Ant.copy(:filesetList = { this.file("classes").fileset() },
                :todir = classesDir)
    }

    // copy in the environment-specific resources
    var warEnvDir = webInfDir.file("env")
    var envDir = this.file("env")
    if(envDir.exists()) {
      warEnvDir.mkDirs()
      Ant.copy(:filesetList = { envDir.fileSet() },
              :todir = warEnvDir)
    }

    // copy in the libraries
    var libDir = webInfDir.file("lib")
    libDir.mkdirs()
    Ant.copy(:filesetList = { this.file("lib").fileset() },
              :todir = libDir)

    // copy in the Gosu libraries
    Ant.copy(:filesetList = { GosuFiles.fileset() },
              :todir = libDir)
    Ant.copy(:filesetList = { GosuFiles.file("../ext").fileset(
              :excludes="*jetty* servlet*") },
              :todir = libDir)

    var warName = this.file(".").ParentFile.Name + ".war"
    var warDest = this.file("build/${warName}")
    Ant.jar(:destfile = warDest,
             :basedir = warDir)

    this.logInfo("\n\n  A java war file was created at ${warDest.AbsolutePath}")
  }

  /* Runs the tests associated with your app */
  @Target
  @Depends({"deps", "compile"})
  @Param("waitForDebugger", "Suspend the server until a debugger connects.")
  @Param("parallelClasses", "Run test classes in parallel.")
  @Param("parallelMethods", "Run test method within a class in parallel.")
  @Param("env", "A comma-separated list of environment variables, formatted as \"ronin.name=value\".")
  @Param("trace", "Enable detailed tracing.")
  function test(waitForDebugger : boolean, parallelClasses : boolean, parallelMethods : boolean, trace : boolean, env : String = "") {
    var cp = this.classpath(this.file("support").fileset())
               .withFileset(this.file("lib").fileset())
               .withFile(this.file("src"))
               .withFile(this.file("test"))
               .withFileset(GosuFiles.fileset())

    Ant.java(:classpath=cp,
                   :classname="ronin.DevServer",
                   :jvmargs=getJvmArgsString(waitForDebugger)
                    + (trace ? " -Dronin.trace=true " : "")
                    + " " + env.split(",").map(\e -> "-D" + e).join(" "),
                   :fork=true,
                   :failonerror=true,
                   :args="test ${this.file(".").AbsolutePath} ${parallelClasses} ${parallelMethods}")
  }

  /* Starts a server and runs the UI tests associated with your app */
  @Target
  @Depends({"deps", "compile"})
  @Param("waitForDebugger", "Suspend the server until a debugger connects.")
  @Param("port", "The port to start the server on (default is 8080).")
  @Param("parallelClasses", "Run test classes in parallel.")
  @Param("parallelMethods", "Run test method within a class in parallel.")
  @Param("env", "A comma-separated list of environment variables, formatted as \"ronin.name=value\".")
  @Param("trace", "Enable detailed tracing.")
  function uiTest(waitForDebugger : boolean, parallelClasses : boolean, parallelMethods : boolean, trace : boolean, port : int = 8080, env : String = "") {
    var cp = this.classpath(this.file("support").fileset())
               .withFileset(this.file("lib").fileset())
               .withFile(this.file("src"))
               .withFile(this.file("test"))
               .withFileset(GosuFiles.fileset())

    Ant.java(:classpath=cp,
                   :classname="ronin.DevServer",
                   :jvmargs=getJvmArgsString(waitForDebugger)
                    + (trace ? " -Dronin.trace=true " : "")
                    + " " + env.split(",").map(\e -> "-D" + e).join(" "),
                   :fork=true,
                   :failonerror=true,
                   :args="uiTest ${port} ${this.file(".").AbsolutePath} ${parallelClasses} ${parallelMethods}")
  }

  /* Runs the tests associated with your app under all possible combinations of environment properties */
  @Target
  @Depends({"deps", "compile"})
  @Param("waitForDebugger", "Suspend the server until a debugger connects.")
  @Param("parallelClasses", "Run test classes in parallel.")
  @Param("parallelMethods", "Run test method within a class in parallel.")
  @Param("trace", "Enable detailed tracing.")
  function testAll(waitForDebugger : boolean, parallelClasses : boolean, parallelMethods : boolean, trace : boolean) {
    doForAllEnvironments(\env -> test(waitForDebugger, parallelClasses, parallelMethods, trace, env), "Testing", "Tested", {"mode"})
  }

  /* Runs the UI tests associated with your app under all possible combinations of environment properties */
  @Target
  @Depends({"deps", "compile"})
  @Param("waitForDebugger", "Suspend the server until a debugger connects.")
  @Param("port", "The port to start the server on (default is 8080).")
  @Param("parallelClasses", "Run test classes in parallel.")
  @Param("parallelMethods", "Run test method within a class in parallel.")
  @Param("trace", "Enable detailed tracing.")
  function uiTestAll(waitForDebugger : boolean, parallelClasses : boolean, parallelMethods : boolean, trace : boolean, port : int = 8080) {
    doForAllEnvironments(\env -> uiTest(waitForDebugger, parallelClasses, parallelMethods, trace, port, env), "Testing", "Tested", {"mode"})
  }

  /* Connects to the admin console of a running app */
  @Target
  @Depends({"deps", "compile"})
  @Param("port", "The port on which the admin console is running.")
  @Param("username", "The username with which to connect to the admin console.")
  @Param("password", "The password with which to connect to the admin console.")
  function console(port : String = "8022", username : String = "admin", password : String = "password") {
    var cp = this.classpath(this.file("support").fileset())
               .withFileset(this.file("lib").fileset())
               .withFile(this.file("src"))
               .withFileset(GosuFiles.fileset(:excludes="*.dll,*.so"))

    Ant.java(:classpath=cp,
                   :classname="ronin.DevServer",
                   :failonerror=true,
                   :args="console ${port} ${username} ${password}")
  }

  function getJvmArgsString(suspend : boolean) : String {
    var debugStr : String
    if(gw.util.Shell.isWindows()) {
      this.logInfo("Starting server in shared-memory debug mode at ${RoninAppName}")
      debugStr = "-Xdebug -Xrunjdwp:transport=dt_shmem,server=y,suspend=${suspend ? "y" : "n"},address=${RoninAppName}"
    } else {
      this.logInfo("Starting server in socket debug mode at 8088")
      debugStr = "-Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=${suspend ? "y" : "n"},address=8088"
    }
    return debugStr
  }

  private function doForAllEnvironments(action(env : String), ing : String, ed : String, exclude : List<String> = null) {
    var environments = allCombinations(this.file("env").Children.where(\f -> exclude == null || !exclude.contains(f.Name))
      .map(\f -> Pair.make(f, f.Children)))
    this.logInfo("${ing} ${environments.Count} environments...")
    for(environment in environments index i) {
      action(environment.map(\e -> "ronin.${e.First.Name}=${e.Second.Name}").join(","))
      this.logInfo("${ed} ${i + 1}/${environments.Count} environments")
    }
  }

  private function allCombinations(m : List<Pair<File, List<File>>>) : List<List<Pair<File, File>>> {
    var rtn : List<List<Pair<File, File>>> = {}
    innerAllCombinations(m, rtn, {})
    return rtn
  }

  private function innerAllCombinations(m : List<Pair<File, List<File>>>, rtn : List<List<Pair<File, File>>>,
                                                                     coll : List<Pair<File, File>>) {
    if(m.Empty) {
      rtn.add(coll.copy())
    } else {
      var entry = m[0]
      m.remove(0)
      for(value in entry.Second) {
        coll.add(Pair.make(entry.First, value))
        innerAllCombinations(m, rtn, coll)
        coll.remove(coll.Count - 1)
      }
      m.add(0, entry)
    }
  }

}