import type { FastifyError, FastifyInstance } from 'fastify';

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly detail?: string,
  ) {
    super(code);
  }
}

export function bad(code: string, detail?: string): HttpError {
  return new HttpError(400, code, detail);
}

export function registerErrorHandler(app: FastifyInstance): void {
  app.setErrorHandler((err: FastifyError, _req, reply) => {
    if (err instanceof HttpError) {
      return reply
        .code(err.status)
        .send(err.detail ? { error: err.code, detail: err.detail } : { error: err.code });
    }
    // Fastify's own client errors (unparseable JSON body, failed schema validation) keep their
    // status. Anything else is unexpected: log the stack, return nothing about it.
    if (err.statusCode !== undefined && err.statusCode < 500) {
      return reply.code(err.statusCode).send({ error: err.code ?? 'bad_request' });
    }
    app.log.error(err);
    return reply.code(500).send({ error: 'internal' });
  });
}
