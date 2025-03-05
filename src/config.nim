# Configuration constants for Medicare Email Scheduler
import times

# System constants
const
  # Number of AEP distribution weeks
  AEP_DISTRIBUTION_WEEKS* = 4

# Email scheduling time frames
const
  # Birthday email schedule timing - days before birthday
  BIRTHDAY_EMAIL_DAYS_BEFORE* = 14
  
  # Effective date email schedule timing - days before effective date
  EFFECTIVE_EMAIL_DAYS_BEFORE* = 30
  
  # Exclusion window calculation
  EXCLUSION_WINDOW_DAYS_BEFORE* = 60  # Verified from EmailRules.md (60-Day Exclusion Window)
  
  # Email overlap threshold for standard case (no state rules)
  EMAIL_OVERLAP_THRESHOLD_DAYS* = 30
  
  # Post-exclusion window timing - days after exclusion window ends
  POST_EXCLUSION_DAYS_AFTER* = 1
  
  # Annual Carrier Update email date (Jan 31)
  CARRIER_UPDATE_MONTH* = mJan
  CARRIER_UPDATE_DAY* = 31
  
  # AEP Week dates
  AEP_WEEK1_MONTH* = mAug
  AEP_WEEK1_DAY* = 18
  
  AEP_WEEK2_MONTH* = mAug
  AEP_WEEK2_DAY* = 25
  
  AEP_WEEK3_MONTH* = mSep
  AEP_WEEK3_DAY* = 1
  
  AEP_WEEK4_MONTH* = mSep
  AEP_WEEK4_DAY* = 7
  
  # Special test cases
  TEST_AEP_OVERRIDE_YEAR* = 2025
  TEST_AEP_OVERRIDE_MONTH* = mAug
  TEST_AEP_OVERRIDE_DAY* = 15
  
  # Default fallback duration for exclusion window
  DEFAULT_EXCLUSION_DURATION_DAYS* = 30
  
  # Safe day of month for yearly date calculations
  SAFE_MAX_DAY* = 28  # Works for all months, including February in leap years
  
# State rule parameters
const
  # State rule default parameters
  TX_BIRTHDAY_OFFSET* = -14
  TX_BIRTHDAY_DURATION* = 30
  
  FL_BIRTHDAY_OFFSET* = -14
  FL_BIRTHDAY_DURATION* = 30
  
  CA_BIRTHDAY_OFFSET* = -30
  CA_BIRTHDAY_DURATION* = 60
  
  ID_BIRTHDAY_OFFSET* = 0
  ID_BIRTHDAY_DURATION* = 63
  
  MO_EFFECTIVE_OFFSET* = -30
  MO_EFFECTIVE_DURATION* = 63