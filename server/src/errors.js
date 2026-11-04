export class HttpError extends Error {
  constructor(status, message, code = 'ERROR') {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    this.code = code;
  }
}

export const badRequest = (message, code = 'BAD_REQUEST') => new HttpError(400, message, code);
export const notFound = (message = 'Not found', code = 'NOT_FOUND') => new HttpError(404, message, code);
export const unauthorized = () => new HttpError(401, 'Unauthorized', 'UNAUTHORIZED');
export const methodNotAllowed = () => new HttpError(405, 'Method not allowed', 'METHOD_NOT_ALLOWED');
