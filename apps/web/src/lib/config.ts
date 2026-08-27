export const API_URL = process.env.CLIPIFY_API_URL ?? "http://localhost:3000";

/** httpOnly cookie holding the Rails JWT. The browser never reads it. */
export const TOKEN_COOKIE = "clipify_token";

/** JWT lifetime in the Rails config (config/initializers/devise.rb). */
export const TOKEN_MAX_AGE = 7 * 24 * 60 * 60;
