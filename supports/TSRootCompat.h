#pragma once

#if __has_include(<TargetConditionals.h>)
#include <TargetConditionals.h>
#endif

#ifndef TARGET_OS_SIMULATOR
#define TARGET_OS_SIMULATOR 0
#endif

#if !TARGET_OS_SIMULATOR && !defined(DISABLE_PATH_REDIRECTION)
#if __has_include(<roothide.h>)
#include <roothide.h>
#ifdef JBROOT_PATH_CSTRING
#undef JBROOT_PATH_CSTRING
#endif
#define JBROOT_PATH_CSTRING(cPath) jbroot(cPath)
#ifdef __OBJC__
#ifdef JBROOT_PATH_NSSTRING
#undef JBROOT_PATH_NSSTRING
#endif
#define JBROOT_PATH_NSSTRING(nsPath) jbroot(nsPath)
#endif
#elif __has_include(<libroot.h>)
#include <libroot.h>
#endif
#endif

#ifndef JBROOT_PATH_CSTRING
#define JBROOT_PATH_CSTRING(cPath) cPath
#endif

#ifdef __OBJC__
#ifndef JBROOT_PATH_NSSTRING
#define JBROOT_PATH_NSSTRING(nsPath) nsPath
#endif
#endif
