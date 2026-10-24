# TheInterview

An immersive job-interview practice app for Apple Vision Pro. You check in at a virtual reception desk, follow the receptionist through the office to an interview room, and answer questions out loud from an interviewer. Afterwards you get a detailed feedback report on your answers, your eye contact and your delivery.

The original product vision is in [`temp_info_placeholder.txt`](temp_info_placeholder.txt).

## What happens in a session

1. **Reception.** The office fades in around you. Ava, the receptionist, waves and greets you by name: *"What position are you applying for today, Ms. Rivera?"* You answer out loud, for example *"I'm applying for a Technical Mechanic."*
2. **The walk.** *"Oh, I see your appointment right here. Follow me this way."* She leads you down the corridor past colleagues at their desks and into the interview room. Turn on **Comfort mode** for a fade instead of the walk.
3. **The interview.** Daniel Park stands to greet you, sits, and asks *"Are you ready to begin?"* He then asks questions written for the role you named. While you answer he listens attentively, nodding now and then. When an answer is vague, lacks an example or leaves out the outcome, he follows up (*"And what was the outcome?"*), up to twice per interview. Say *"that's my answer"*, pause, or tap **Done** to finish an answer. You can also ask him to repeat a question, or type instead of speaking. At the end he asks *"Do you have any questions for me?"* and answers up to two of yours.
4. **The report.** You get an overall score, with a breakdown of how much came from your answers (70%), your delivery (15%) and your eye contact (15%). It also shows speaking pace, filler words, long pauses and speaking time, plus strengths and things to work on. Every question gets a score, feedback, a concrete tip and, with an AI provider, an example of how a stronger answer might sound. Reports are saved and can be shared as text.

## Requirements

- Xcode 16 or later with the visionOS 2 SDK (the project uses Xcode 16's synchronized folders)
- Apple Vision Pro running visionOS 2 or later, or the visionOS simulator
- Optional: an OpenAI API key, or visionOS 26 with Apple Intelligence for free on-device AI

## Getting started

1. Open `TheInterview.xcodeproj`.
2. Select the **TheInterview** target, then **Signing & Capabilities**. Choose your team and, if needed, change the bundle identifier (`com.theinterview.TheInterview`).
3. Choose a Vision Pro device or the visionOS simulator and press **Run**.
4. Optional: in the app, open **Settings**, paste your OpenAI API key and tap **Test connection**. For simulator runs you can also set an `OPENAI_API_KEY` environment variable in your own (unshared) scheme.

Without a key the app still works end to end, using its built-in question bank and on-device scoring.

### Running the tests

The interview logic lives in a Swift package with no Apple-only dependencies, so its tests run anywhere Swift does:

```sh
cd Packages/InterviewCore
swift test
```

In Xcode, **Product > Test** (⌘U) runs the same tests from the shared scheme.

## How it works

```
TheInterview/                 visionOS app (SwiftUI, RealityKit, ARKit, AVFoundation, Speech)
  App/                        App entry point, AppModel (state and flow), settings
  Immersive/                  The 3D office, characters and their animation, stage choreography
  Services/                   Speech in and out, head-pose tracking, Keychain
  Views/                      Home, settings, in-office control panel, feedback report
Packages/InterviewCore/       Platform-independent logic (unit tested)
  Engine/                     InterviewEngine: the scripted flow from reception to report
  AI/                         OpenAI client, prompts, question/reaction/evaluation services
  Analysis/                   Reply parsing, speech metrics, attention maths, on-device evaluator
  Questions/                  Built-in question bank
  Persistence/                Report storage
```

`InterviewEngine` owns the order of events and the script. Speech, the 3D stage, head tracking and the network are injected through small protocols (`VoiceOutput`, `VoiceInput`, `StageDirecting`, `AttentionTracking`, `QuestionGenerating`, `InterviewEvaluating`). This lets the whole interview run in tests with scripted replies.

### The office

The office, its furniture and the seven-person cast are built procedurally from RealityKit primitives, so the project has no 3D asset dependencies.

- **Surfaces** use textures drawn in code at real-world scale: wood-plank and stone-tile floors, carpet tiles, ceiling tiles, wood grain and patterned rugs.
- **Characters** are jointed figures with eyes that blink, lips that move as they talk, and hands that gesture. They breathe, shift their weight, walk, type and wave, and they turn their heads to look at you. While you speak they listen attentively, with small nods and a tilt of the head.
- **Voices** are rendered with the system speech synthesizer and played from each character's mouth with spatial audio, so they come from where the person is standing.
- **Movement:** when you're led to the interview room, it is the office that moves around you, not you; you stay where you are.
- **Ambience** (room tone, distant voices, keyboards) is a generated loop in `TheInterview/Resources`.

### Listening to answers

- **Knowing when you've finished.** A fixed silence timeout either cuts people off mid-thought or leaves them waiting, so the wait adapts to what you've said. If you trail off on "…and", "um" or "let me think", it waits almost twice as long. After a finished sentence in a substantial answer it moves on sooner. Saying "that's my answer" or tapping **Done** always works.
- **Pace and pauses from word timings.** When an answer ends, the app asks the speech recognizer for its final result, which includes the timing of every word. Speaking pace is measured from those timings, and pauses of two seconds or more are counted.
- **Understanding short replies.** Job titles are pulled out of natural phrasing ("I'm here about the accounts payable job" gives *Accounts Payable*). "Not yet", "give me a second" and "can you repeat that?" are recognized. At the end, real questions are told apart from polite declines like "No, I think you've covered everything".

### Questions and feedback

- **AI provider.** In Settings, choose **Automatic** (the default), **OpenAI**, **Apple Intelligence** or **Built-in only**. Automatic uses OpenAI when a key is saved, otherwise Apple Intelligence when the device supports it, otherwise the built-in rules.
- **Apple Intelligence** is Apple's on-device foundation model. It's free, needs no account and nothing leaves the device. It requires visionOS 26 with Apple Intelligence turned on and a project built with Xcode 26 or later. It's a smaller model than OpenAI's, so prompts include shorter answer excerpts and its feedback is less detailed.
- **With OpenAI**, questions are generated for the exact position you name, at your chosen level and focus. After each answer the model writes the interviewer's brief reaction and decides whether a follow-up question is warranted. After the interview the transcript and measurements are sent for evaluation; the model writes the scores, the feedback, and an example stronger answer for each question. Requests use the Chat Completions API in JSON mode. The model is configurable in Settings (default `gpt-4.1-mini`).
- **Measured numbers always come from the device**: words per minute, filler words, pauses, speaking time and eye contact. The AI scores the answers' content using an explicit rubric, and the overall score combines that with the measured delivery and eye-contact scores.
- **If there's no key, or a request fails or times out**, the app falls back to its built-in question bank and an on-device evaluator. The evaluator scores relevance, clarity and structure, including STAR structure for behavioral questions. On-device rules also decide follow-ups: answers that are very brief, have no concrete example, or tell a story without its outcome get probed.
- **Follow-up replies** count toward the answer's score, as they would in a real interview. Follow-ups can be turned off in Settings.
- **What the scoring looks for**:
  - Relevance to the question and to what it's probing for.
  - Concrete examples and measurable results, with STAR structure for behavioral questions.
  - Your own contribution: saying "I", not only "we".
  - Conciseness, without repetition or rambling.
  - Confidence: few hedges, and not opening with "I don't know".
  - A constructive tone, especially about past employers.
- **Delivery** is scored on pace (120–160 words per minute is comfortable), filler words, hedging and long pauses.

### Eye contact

visionOS doesn't give apps access to eye-tracking data; where you look stays private to the system. The Vision framework can't see your eyes either. So TheInterview estimates eye contact from **head pose**, which ARKit's world tracking does provide. You count as engaged while your head faces the interviewer's eyes, within about 20° horizontally and 18° vertically. Glances shorter than a second lower the percentage but aren't counted as separate look-aways. This is a reasonable stand-in, since people turn their heads toward whoever they're looking at, but it can't detect eyes moving while the head stays still. Head tracking needs a real device; in the simulator the report notes that eye contact wasn't tracked.

### Privacy

- Speech is recognised on device where supported.
- Transcripts leave the device only when OpenAI is the provider in use; the key is kept in the Keychain. Apple Intelligence runs entirely on the device.
- Reports are stored locally in Application Support.

## Using free 3D models for more realism

The built-in office and people are stylised. You can make them much more realistic with free assets. Drop the files into the `TheInterview/Resources` folder and they're used automatically; anything you don't add falls back to the built-in version.

### People (Mixamo, free)

1. At [mixamo.com](https://www.mixamo.com) (free with an Adobe account), pick a character for the receptionist and one for the interviewer. Download each as **FBX, With Skin**.
2. Download these animations for one of the characters as **FBX, Without Skin**, with **In Place** ticked for walking. Animations from one character work for both, because Mixamo characters share a skeleton.

   | File name | Mixamo animation (search term) | Required |
   |---|---|---|
   | `Anim_Idle` | Idle | yes |
   | `Anim_Walk` | Walking (In Place) | yes |
   | `Anim_Sit` | Sitting Idle | yes |
   | `Anim_Talk` | Talking | recommended |
   | `Anim_SitTalk` | Sitting Talking | recommended |
   | `Anim_Wave` | Waving | optional |
   | `Anim_Point` | Pointing | optional |
   | `Anim_Nod` | Head Nod Yes | optional |
   | `Anim_SitDown` / `Anim_StandUp` | Stand To Sit / Sit To Stand | optional |
   | `Anim_Type` | Typing | optional |

3. Convert every file to USDZ with Apple's free **Reality Converter**. If it won't open the FBX, import it into **Blender** (free) and export as USD instead.
4. Name the characters `Receptionist.usdz` and `Interviewer.usdz`, and the animations as in the table, for example `Anim_Idle.usdz`.

Characters are scaled to a realistic height automatically. They should face forward (+Z) with their feet at the origin, which is how Mixamo exports them.

### The office

Export an office scene as `Office.usdz`. It can be built in Blender from free assets: [Poly Haven](https://polyhaven.com) has CC0 textures, lighting and furniture, and [Sketchfab](https://sketchfab.com) has free models under CC licences (credit the authors).

To tell the app where things are, add empty objects ("empties" in Blender) with these names:

| Name | What it marks |
|---|---|
| `ReceptionistSpot` | Where the receptionist stands behind the desk |
| `InterviewerChair` | The interviewer's chair |
| `CandidateSeat` | Where you end up, facing the interviewer |
| `ReceptionistRoomSpot` | Where the receptionist stands after showing you in |
| `Route1`, `Route2`, … | The path from reception to the interview room |

You start at the origin facing -Z. Put the reception desk in front of you and arrange the room so the interviewer is in the -Z direction from `CandidateSeat`.

### How far this can go

- **Mixamo** gives good game-quality people for free, but not photoreal faces, and there's no lip-sync.
- **Epic's MetaHuman** is free and the closest to photoreal. It's a heavier route: export from Unreal Engine, simplify the hair and textures for Vision Pro, and check that the current licence covers your use outside Unreal Engine.
- **Performance:** keep the whole scene to a few hundred thousand triangles, with 2K textures or smaller, so it stays smooth on Vision Pro.

## Customising

- **Company name**: in Settings; it appears on the lobby wall and in the receptionist's greeting.
- **Characters' names and script**: `InterviewConfiguration` and `InterviewScript` in the core package.
- **Office layout**: `OfficeBuilder.swift` (the layout diagram is in its header comment), or your own `Office.usdz` with markers (see above).
- **Built-in questions**: `QuestionBank.swift`.
