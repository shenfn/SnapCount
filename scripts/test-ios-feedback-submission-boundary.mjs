import assert from 'node:assert/strict'
import fs from 'node:fs'

const appState = fs.readFileSync('ios/SnapCount/App/AppState.swift', 'utf8')
const repository = fs.readFileSync('ios/SnapCount/Repositories/RecordRepository.swift', 'utf8')
const recordsView = fs.readFileSync('ios/SnapCount/Features/Records/RecordsView.swift', 'utf8')
const inboxView = fs.readFileSync('ios/SnapCount/Features/Inbox/InboxView.swift', 'utf8')

assert.match(repository, /func submitFeedback\(/)
assert.match(repository, /submit_expression_feedback/)
assert.match(appState, /func submitRecordFeedback\(/)
assert.match(appState, /feedbackSubmissionUseCase/)
assert.doesNotMatch(recordsView, /recordRepository/)
assert.doesNotMatch(inboxView, /recordRepository/)
assert.doesNotMatch(appState, /recordFeedbackState = \.submitted[\s\S]*?recordRepository\.submitFeedback/)

console.log('iOS feedback submission boundary checks passed')
