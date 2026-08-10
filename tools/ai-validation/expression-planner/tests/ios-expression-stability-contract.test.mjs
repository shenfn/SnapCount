import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..')
const feedback = await readFile(path.join(root, 'ios/SnapCount/Models/NativeAIFeedback.swift'), 'utf8')
const appState = await readFile(path.join(root, 'ios/SnapCount/App/AppState.swift'), 'utf8')
const records = await readFile(path.join(root, 'ios/SnapCount/Features/Records/RecordsView.swift'), 'utf8')
const inbox = await readFile(path.join(root, 'ios/SnapCount/Features/Inbox/InboxView.swift'), 'utf8')

test('EXP-008 preserves Voice slot when an independent Planner card arrives', () => {
  assert.match(feedback, /plannerFeedbackToDisplayWithoutReplacingVoice/)
  assert.match(feedback, /feedbackCardsToRender/)
  assert.match(feedback, /feedbackForReview/)
  assert.match(appState, /plannerFeedbackToDisplayWithoutReplacingVoice/)
  assert.match(appState, /feedbackIdentity: String\? = nil/)
  assert.match(records, /feedbackCardsToRender/)
  assert.match(inbox, /feedbackCardsToRender/)
  assert.doesNotMatch(records, /expressionPlannerAiFeedback\s*\?\?\s*detail\.voiceAiFeedback/)
  assert.doesNotMatch(inbox, /expressionPlannerAiFeedback\s*\?\?\s*detail\.voiceAiFeedback/)
  assert.doesNotMatch(records, /submitRecordFeedback\(choice: choice, freeText: text\)/)
  assert.doesNotMatch(inbox, /submitRecordFeedback\(choice: choice, freeText: text\)/)
})
