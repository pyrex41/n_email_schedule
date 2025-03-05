import tables
import config

type
  StateRule* = enum
    Birthday, Effective, YearRound, None

  RuleParams* = tuple
    startOffset: int   # days before reference date
    duration: int      # period duration in days

const
  StateRules = {
    # Birthday states
    "CA": (rule: Birthday, params: (CA_BIRTHDAY_OFFSET, CA_BIRTHDAY_DURATION)),  # 60-day period, 30 days before
    "ID": (rule: Birthday, params: (ID_BIRTHDAY_OFFSET, ID_BIRTHDAY_DURATION)),    # 63-day period from birthday
    "IL": (rule: Birthday, params: (0, 45)),    # 45-day period from birthday
    "KY": (rule: Birthday, params: (0, 60)),    # 60-day period from birthday
    "LA": (rule: Birthday, params: (-30, 93)),  # 93-day period, 30 days before
    "MD": (rule: Birthday, params: (0, 31)),    # 31-day period from birthday
    "NV": (rule: Birthday, params: (0, 60)),    # 60-day period from birth month
    "OK": (rule: Birthday, params: (0, 60)),    # 60-day period from birthday
    "OR": (rule: Birthday, params: (0, 31)),    # 31-day period from birthday
    "TX": (rule: Birthday, params: (TX_BIRTHDAY_OFFSET, TX_BIRTHDAY_DURATION)),  # From config.nim
    "FL": (rule: Birthday, params: (FL_BIRTHDAY_OFFSET, FL_BIRTHDAY_DURATION)),  # From config.nim
    
    # Effective date states
    "MO": (rule: Effective, params: (MO_EFFECTIVE_OFFSET, MO_EFFECTIVE_DURATION)), # From config.nim
    
    # Year-round states
    "CT": (rule: YearRound, params: (0, 0)),
    "MA": (rule: YearRound, params: (0, 0)),
    "NY": (rule: YearRound, params: (0, 0)),
    "WA": (rule: YearRound, params: (0, 0))
  }.toTable

proc getStateRule*(state: string): StateRule =
  if state in StateRules:
    result = StateRules[state].rule
  else:
    result = None

proc getRuleParams*(state: string): RuleParams =
  if state in StateRules:
    result = StateRules[state].params
  else:
    result = (0, 0) 