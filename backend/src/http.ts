export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(code);
  }
}

export function bad(code: string): HttpError {
  return new HttpError(400, code);
}
