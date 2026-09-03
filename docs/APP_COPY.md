# App copy — project_icarus

Every non-Learn string the app shows, keyed by `CopyKey` (R42). The owner
approves every line here (S17). `scripts/build-app-copy.sh` (M3) turns this
file into `Sources/IcarusContent/Resources/app-copy.json`; views never hold a
literal. Learn text is not here: it lives in `docs/LEARN_CONTENT.md` and is
rendered verbatim (V5).

Format, read by the build script:

- One `### <CopyKey>` heading per key, spelled exactly as the enum case.
- Under it, `- base:` is the text for every skin type. An optional `- fair:`
  line replaces it for types I and II.
- Values the engine fills in are written in `{braces}`. The argument names
  are part of the contract: `{minutes}`, `{sideMinutes}`, `{frontMinutes}`,
  `{backMinutes}`, `{region}`, `{hours}`, `{place}`, `{days}`, `{peakUVI}`,
  `{shortfall}`, `{nextDay}`, `{nextHour}`, `{spf}`, `{application}`,
  `{multiple}`, `{times}`, `{percent}`, `{count}`, `{cycleDose}`,
  `{coveredMinutes}`, `{sed}`, `{window}`, `{pauseDays}`.
- A Learn link is written as `[Module N]`; the view turns it into the deep
  link `icarus://learn/N`.
- The skin-type table and the quiz are the two non-keyed sections at the end.

Tone (R36, V10, V13): frank, plain, never "safe", never a lecture. Estimates
are estimates. Numbers are what the user is told to do; ranges say how sure
the app is.

## Outcomes

### planBareSubWindow
- base: Best {minutes} minutes, no sunscreen. Your slot is longer than your skin needs today, so these are the minutes to take.

### planStayWearThis
- base: To stay the whole {window}, wear {spf}, applied {application}. The bare-skin alternative is below.

### planStayWholeWindowFits
- base: The whole {window} fits under today's budget. Stay for all of it, no sunscreen needed for the tan.

### tooWeak
- base: This slot will not build lasting colour. It delivers {shortfall} SED less than your skin needs for new pigment. The next slot that can is {nextDay} around {nextHour}.

### noViableWindow
- base: No slot in the next {days} days reaches a useful dose. The highest UV index in the forecast is {peakUVI}. This app does not guess past its forecast.

### windowPassed
- base: That slot has already passed. Enter a slot that ends after now.

### budgetSpent
- base: Today's budget for your {region} is used up. More sun today buys damage, not colour. Tomorrow starts a fresh budget.

### missingForecast
- base: No forecast is available, so there is no number to show. Reason: {reason}. Refresh, or check the place the forecast is for.

### missingForecastNoLocation
- base: The app does not know where you are, and there is no saved forecast. Allow location, or enter a place.

## Notices

### staleHeadsUp
- base: Forecast fetched {hours} hours ago for {place}.

### staleWarn
- base: The forecast is {hours} hours old and may be outdated. The number is shorter and the range wider until it is refreshed.

### staleFarFromCache
- base: The saved forecast is for {place}, which is not where you are. The number is shorter and the range wider until you refresh or change the place.

### escalationRisen
- base: Your threshold has risen since this tan cycle began. A fixed dose would no longer trigger new pigment, so today's dose is larger. Cycle dose so far: {cycleDose} SED. [Module 6]

### toleranceDropped
- base: Your tolerance has dropped by about {percent}% since your last session. Today's dose is smaller than the last one you did. [Module 6]

### ceilingReached
- base: The last {count} lasting-colour answers were "no" near modelled saturation, and this cycle has shown a redness report. You have likely reached your skin's maximum. More dose buys damage without colour. The dose drops to maintenance.

### underDosed
- base: The last {count} lasting-colour answers were "no" near modelled saturation, but this cycle has shown no redness, so the app cannot tell whether the dose is too low or your skin is done. At this tan state a maintenance dose keeps what you have.

### maintenance
- base: Maintenance dose: {percent}% of your usual target. It changes back after a "yes" or "a little" to the lasting-colour question.

### thinMargin
- base: For your skin type the dose that tans and the dose that turns skin red are close together. Deciding a tan is not worth it is a reasonable conclusion. This app will not push you either way. [Module 5]

### fairSkinPreCalibration
- base: The first sessions are set below the dose that reliably tans fair skin, on purpose, so that a first redness report arrives at a low dose.

### conservativeUntilCalibrated
- base: Shorter until the app has learned your skin. It uses the conservative setting until you have sent {count} skin reports.

### aggressiveLocked
- base: Aggressive unlocks after {count} skin reports with at least one redness report in the current tan cycle. The app needs to have seen where your line is.

### uvaHeavy
- base: This slot is far from solar noon. The light is UVA-heavy: more ageing per unit of lasting colour. [Module 3]

### cloudCaveat
- base: The forecast already includes expected cloud. Real conditions vary, and thin cloud passes most UV.

### coverToRunLonger
- base: With a hat or shirt on head and shoulders, each side could run {minutes} minutes longer.

### boundByMelanogenic
- base: Today's target is your tanning dose, which sits below your redness line. [Module 5]

### boundByBurnLine
- base: Today's target is set by your redness line. For your skin type the tanning dose is at that line, not below it. [Module 5]

### whichSideFirst
- base: Which side is up first?

### timerStoppedAtPlannedEnd
- base: The timer was still running at midnight. The session was stopped at its planned end.

### timerNeedsNotifications
- base: Notifications are off, so the timer cannot alert you with the screen locked. Turn them on in Settings, or keep the screen on.

### timerCannotStart
- base: The timer cannot start: there is no session to run. {reason}

### oneSideSpent
- base: Your {region} has no budget left today, so that side gets no minutes. The other side is solved on its own.

## Warnings

### warnPastTarget
- base: Staying the whole {window} takes your {region} past today's target, to {sed} SED. Expect more damage than colour.

### warnReachesThreshold
- base: Staying the whole {window} reaches your {region}'s redness threshold, {sed} SED. Expect redness the next day: this is the dose at which skin cells die and the inflammation Module 7 describes begins. [Module 7]

## Sunscreen

### sunscreenNotNeeded
- base: No sunscreen is needed for the tanning goal in these minutes. You may still wear it; then the tan takes longer.

### sunscreenPrescribed
- base: Wear {spf}, applied {application}. That covers every exposed region for the whole {window}.

### sunscreenApplicationBeatsLabel
- base: How much you apply matters more than the number on the bottle: half the amount gives about the square root of the label. A moderate SPF applied properly beats a high SPF applied thinly. [Module 8]

### uvaMultiple
- base: The same tanning dose spread over {multiple} times the minutes carries about {multiple} times the UVA. Sunscreen filters UVB more than UVA unless it carries a UVA rating. [Module 3] [Module 8]

### reapply
- base: Reapply at {times}.

### nothingRealistic
- base: No realistic product covers this slot. Even SPF 50 applied normally is not enough. Shorten the slot instead.

### alternativeWholeWindow
- base: {spf} applied {application} covers the whole {window}.

### alternativeThickEnough
- base: {spf} is enough if you apply it thickly: about a shot glass for the whole body. Applied normally it is not.

### alternativeShadeForRest
- base: {spf} applied {application} covers the first {coveredMinutes} minutes. Shade for the rest of the {window}, and cover head and shoulders.

### didYouWearIt
- base: Did you wear {spf}, applied {application}?

## Prompts

### didYouDoThisSession
- base: Did you do this session? {window}

### noSessionToReport
- base: No session was logged for this day, so there is nothing to report. Nothing was recorded.

### immediateDarkeningExplained
- base: Redness that shows within an hour and is gone by evening is immediate darkening, not a burn. The report was counted as "normal". [Module 2]

### revisitSkinType
- base: Your reports put your sensitivity outside the range for your skin type. Check your skin type in Settings.

### pauseSuggested
- base: Blistering means the dose was far past your line. The estimate was corrected at once. Pause for {pauseDays} days and let the skin recover. [Module 7]

### reportRecorded
- base: Report saved. {effect}

### alreadyReported
- base: This day already has a skin report. One report per day is all the app uses.

## Settings and History

### sensitivitySentence
- base: {percent}% {direction} sensitive than typical for your skin type, based on {count} skin reports.

### deleteHistoryWarning
- base: Deleting the history starts the app over from your skin-type prior. Calibration, tan state, today's budget and History are all lost. Export first if you want to keep them.

### trajectoryTitle
- base: Dose per tan cycle, in SED. This is a record of dose, not a measurement of colour.

### unreportedDays
- base: {count} session days have no skin report.

### privacyOptions
- base: Privacy options for the ad banner.

### importApplied
- base: Import complete: {count} sessions and {reports} reports. The file's profile was applied.

### importFailed
- base: The file could not be read. Nothing was changed.

## Onboarding

### onboardingWhyLocation
- base: Location is used for one thing: fetching the UV forecast for where you are. It never leaves the phone except in that request.

### onboardingWhyNotifications
- base: Notifications carry the day-after skin check, the lasting-colour question and the flip-timer alerts. Without them the same questions wait for the next launch, and the timer cannot alert with the screen locked.

### disclaimer
- base: This app is not medical advice and does not diagnose or treat anything. It estimates a dose from a forecast and from what you report; the estimate can be wrong. Any tan is a sign of skin damage, and there is no dose of ultraviolet light that is known to be free of risk. If you have a skin condition, take medication that affects sun sensitivity, or are unsure, ask a doctor. Sunbeds are outside this app's scope and are not recommended.

## Skin types

The onboarding table. Citation: Fitzpatrick TB. *The validity and practicality of sun-reactive skin types I through VI.* Archives of Dermatology, 1988. https://doi.org/10.1001/archderm.1988.01670060015008

| Type | Name | Description |
| --- | --- | --- |
| I | Type I | Skin goes red after a short time in strong sun and does not turn brown afterwards. Often very fair skin, light eyes, red or very light hair, freckles. |
| II | Type II | Skin goes red easily and turns only slightly brown afterwards. Often fair skin, light or hazel eyes, blond or light brown hair. |
| III | Type III | Skin sometimes goes red, then turns brown gradually. Often light to medium skin, any eye colour, brown hair. |
| IV | Type IV | Skin rarely goes red and turns brown easily. Often olive or light brown skin, dark eyes, dark hair. |
| V | Type V | Skin very rarely goes red and turns dark brown readily. Often brown skin, dark eyes, dark hair. |
| VI | Type VI | Skin does not go visibly red under ordinary sun. Deeply pigmented skin. |

## Fitzpatrick quiz

The published questionnaire. Each answer scores 0 to 4 in the order listed.
Total 0–6: type I; 7–12: type II; 13–18: type III; 19–24: type IV; 25–30:
type V; 31 and above: type VI. Citation: Fitzpatrick 1988, as above.

1. What colour are your eyes? — Light blue, grey or green | Blue, grey or green | Blue | Dark brown | Brownish black
2. What is your natural hair colour? — Red or light blond | Blond | Chestnut or dark blond | Dark brown | Black
3. What colour is your skin where it is not exposed to the sun? — Reddish | Very pale | Pale with a beige tint | Light brown | Dark brown
4. Do you have freckles on unexposed areas? — Many | Several | Few | Incidental | None
5. What happens when you stay in the sun too long? — Painful redness, blistering, peeling | Blistering followed by peeling | Burns sometimes followed by peeling | Rare burns | Never had burns
6. To what degree do you turn brown? — Hardly or not at all | Light colour tan | Reasonable tan | Tan very easily | Turn dark brown quickly
7. Do you turn brown within several hours after sun exposure? — Never | Seldom | Sometimes | Often | Always
8. How does your face react to the sun? — Very sensitive | Sensitive | Normal | Very resistant | Never had a problem
9. When did you last expose your body to the sun, a sunbed or a tanning cream? — More than 3 months ago | 2–3 months ago | 1–2 months ago | Less than a month ago | Less than 2 weeks ago
10. Did you expose the area to be treated to the sun? — Never | Hardly ever | Sometimes | Often | Always

## Notification texts

These keys are not yet in `CopyKey`. The plan that wires the notification
adapter adds them to the enum and to this file in the same change (M2 or M5);
the wording is approved here so that change carries no new copy.

### notificationSkinCheck
- base: How does your skin look today? One skin report for {day}.

### notificationLastingColour
- base: Did you notice lasting colour from {day}?

### notificationTimerSideEnd
- base: Time to turn over.

### notificationTimerReapply
- base: Time to reapply sunscreen.

### notificationTimerSessionEnd
- base: Session over. Time to get out of the sun.
