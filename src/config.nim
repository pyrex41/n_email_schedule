# config.nim
# Centralized configuration for the Medicare Email Scheduler

import logging

# Email scheduling constants
const
  # Number of days before birthday/effective date to send emails
  BirthdayDaysBefore* = 14
  EffectiveDaysBefore* = 30
  
  # Email spacing rule (minimum days between emails)
  EmailSpacingDays* = 60
  
  # Lead time before statutory exclusion window (days)
  StatutoryExclusionLeadDays* = 60

# Logging configuration
const
  LogFileName* = "scheduler.log"
  DefaultLogLevel* = "info" # Options: debug, info, warning, error 

# Centralized logger initialization function
proc getLogger*(moduleName: string): Logger =
  ## Returns a configured logger for the specified module
  result = newFileLogger(LogFileName, fmtStr="[$time] - $levelname: $module - ", bufSize=0)
  result.levelThreshold = 
    case DefaultLogLevel
    of "debug": lvlDebug
    of "info": lvlInfo
    of "warning": lvlWarn
    of "error": lvlError
    else: lvlInfo 