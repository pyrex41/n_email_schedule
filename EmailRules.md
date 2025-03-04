# Email Rules
Below is a clear and explicit summary of the new email scheduling rules based on your query. This synthesis aligns the requirements you provided into a structured format to ensure we're on the same page before discussing the necessary changes to the codebase.

## New Email Scheduling Rules
**1. Email Types and Scheduling**
* **Birthday Emails**:
  * Send **2 weeks (14 days) before** the contact's birthday.
  * Purpose: Notify contacts in advance of their birthday.
* **Effective Date Emails**:
  * Send **30 days before** the contact's policy effective date.
  * Purpose: Remind contacts ahead of their policy renewal or anniversary.
* **Annual Enrollment Period (AEP) Emails**:
  * Scheduling uses specific dates across four weeks:
    * Week 1: August 18
    * Week 2: August 25
    * Week 3: September 1
    * Week 4: September 7
  * Distribution logic:
    * **Single Contact**: Try Week 1 first. If it falls in an exclusion window, try Week 2, then Week 3, then Week 4. If all dates fall in exclusion windows, no AEP email is sent.
    * **Multiple Contacts**: 
      * Initially assign contacts sequentially to weeks (first contact to Week 1, second to Week 2, etc., cycling through the four weeks).
      * For each contact, check if their assigned date falls in an exclusion window. If it does, try other weeks in order until finding a date outside any exclusion window.
      * If no suitable date is found, that contact doesn't receive an AEP email.
  * Note: Replaces the previous October 1st scheduling; now categorized explicitly as "AEP" emails.
* **Eliminated Emails**:
  * New Year emails (previously sent January 2nd) are **no longer sent**.

**2. Exclusion Rules**
* **60-Day Exclusion Window**:
  * No two emails (Birthday, Effective Date, AEP) should be scheduled within **60 days** of each other.
  * If multiple emails fall within a 60-day window, prioritize as follows:
    **1** **Effective Date Email**: Always send this email on its scheduled date (30 days before effective date).
    **2** **AEP Email**: Try to send on its scheduled date, but if it falls in an exclusion window, try alternative weeks as described above.
    **3** **Birthday Email**: Do not send if it falls within 60 days of an Effective Date or AEP email. It is skipped entirely in this case, not rescheduled.
* **State-Specific Rule Windows**:
  * Applies to states with special rules (e.g., birthday rule states like CA, ID, IL, etc., and Missouri with an effective date rule).
  * **Extended Exclusion Period**:
    * No emails (Birthday, Effective Date, or AEP) should be sent during the state's defined rule window **or** in the **60 days before the rule window starts**.
    * Example: If a state's birthday rule window is 30 days before to 30 days after the birthday (60 days total), the total exclusion period becomes 90 days before the birthday (60 days prior + 30 days before) to 30 days after the birthday—a 120-day window where no emails are sent.
  * **AEP Email Handling**: 
    * If an AEP email falls within this extended window, try alternative weeks as described above.
    * If no week works, the AEP email is not sent ("tough luck").
  * States affected:
    * Birthday rule states (e.g., CA, ID, IL, KY, LA, MD, NV, OK, OR).
    * Missouri (effective date rule).

**3. Post-Rule Window Email**
* After the state-specific rule window ends (including the 60-day prior exclusion), send **one email**:
  * **Birthday Rule States**: Send a Birthday email (replacing any missed Birthday, Effective Date, or AEP emails).
  * **Missouri**: Send an Effective Date email (replacing any missed emails).
* Timing: Sent immediately after the rule window ends (e.g., the day after the window closes).
* Limitation: Only one email is sent, regardless of how many were suppressed during the window.

**4. Additional Notes**
* **No Overlap Handling Beyond Prioritization**: If emails are excluded due to the 60-day rule or state-specific windows, they are not rescheduled unless explicitly stated (e.g., post-rule window email).
* **AEP Distribution Logic**: 
  * Contacts are assigned to weeks sequentially (1st contact to Week 1, 2nd to Week 2, etc.)
  * For each contact, if their assigned week conflicts with an exclusion window, alternative weeks are tried in order
  * If no viable week is found, the contact receives no AEP email

## Clarifications for Alignment
To ensure the logic is airtight, here are a few points I've inferred or assumed based on your description. Please confirm or adjust these:
**1** **AEP Distribution Priority for Exclusion Window Checks**:
  * When an assigned week conflicts with an exclusion window, we try the other weeks in sequence (Week 1, 2, 3, 4) regardless of which week was initially assigned.
**2** **60-Day Exclusion Prioritization**:
  * If both an Effective Date email and an AEP email fall within 60 days of each other, both are sent (since they are both prioritized over Birthday emails). Confirm this is intended.
**3** **State Rule Window Duration**:
  * Existing window durations (e.g., CA: 60 days, MO: 63 days) are assumed to remain unchanged, with the 60-day prior exclusion added.
**4** **Post-Window Email Timing**:
  * Sent the day after the rule window ends.
**5** **Email Type After Extended Rule Window**:
  * For Birthday rule states, only a Birthday email is sent after the rule window, even if an Effective Date email would have been sent during that window.
  * For Missouri, only an Effective Date email is sent after the rule window.
