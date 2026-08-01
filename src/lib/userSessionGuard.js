export function canLoadBusinessData(isLoggedIn, authGate) {
  return isLoggedIn === true && authGate === 'none'
}

export function isSameSessionUser(session, userId) {
  return Boolean(session?.user?.id && userId && session.user.id === userId)
}

export function createUserDataContext(userId, generation) {
  return {
    userId: typeof userId === 'string' && userId ? userId : null,
    generation,
  }
}

export function isUserDataContextCurrent(context, { userId, generation, isLoggedIn }) {
  return Boolean(
    context?.userId
      && context.userId === userId
      && context.generation === generation
      && isLoggedIn === true,
  )
}
