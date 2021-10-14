/* 
 * Copyright (C) 2021 by phantom
 * Email: phantom@zju.edu.cn
 * This file is under MIT License, see https://www.phvntom.tech/LICENSE.txt
 */

Global / lintUnusedKeysOnLoad := false

lazy val commonSettings = Seq(
  organization := "zjv",
  version := "0.1",
  scalaVersion := "2.12.10",
  scalacOptions ++= Seq(
    "-deprecation",
    "-feature",
    "-unchecked",
    "-Xsource:2.11",
    "-language:reflectiveCalls"
  ),
  libraryDependencies ++= Seq(
    "com.github.scopt" %% "scopt" % "3.7.1"
  )
)

lazy val rocket_chip = RootProject(file("repo/rocket-chip"))

lazy val startship_soc = (project in file("."))
  .dependsOn(rocket_chip, zjv2_core, sezjv_core, sifive_blocks, fpga_shells)
  .settings(commonSettings: _*)

lazy val sifive_blocks = (project in file("repo/sifive-blocks"))
  .dependsOn(rocket_chip)
  .settings(commonSettings: _*)

lazy val fpga_shells = (project in file("repo/fpga-shells"))
  .dependsOn(rocket_chip, sifive_blocks)
  .settings(commonSettings: _*)

lazy val zjv2_core = (project in file("repo/ZJV2"))
  .dependsOn(rocket_chip)
  .settings(commonSettings: _*)

lazy val sezjv_core = (project in file("repo/SEZJV1"))
  .dependsOn(rocket_chip)
  .settings(commonSettings: _*)