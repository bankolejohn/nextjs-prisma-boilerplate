const path = require('path');

module.exports = {
  reactStrictMode: true,
  trailingSlash: true,
  // Note: experimental.runtime, serverComponents, and reactRoot removed —
  // they forced SWC compilation which requires OpenSSL 1.1 (unavailable on Ubuntu 24.04).
  // .babelrc is present so Next.js uses Babel automatically, which is cross-platform.
  /*
  webpackDevMiddleware: (config) => {
    config.watchOptions = {
      poll: 1000,
      aggregateTimeout: 300,
    };
    return config;
  },
  */
  sassOptions: {
    includePaths: [path.join(__dirname, 'styles')],
  },
  // buildtime, must provide buildtime in Dockerfile or hardcode
  env: {
    // used in axios instance, just rename it
    // with '/', no need to trim it anywhere
    // all paths have '/'
    NEXT_PUBLIC_BASE_URL: `${process.env.NEXTAUTH_URL}/`,
    NEXT_PUBLIC_POSTS_PER_PAGE: 5,
    NEXT_PUBLIC_USERS_PER_PAGE: 3,
    NEXT_PUBLIC_DEFAULT_THEME: 'theme-blue',
  },
  // runtime, server, private
  serverRuntimeConfig: {
    // just forward entire env.local
    // only used in [...nextauth]
    SECRET: process.env.SECRET,
    FACEBOOK_CLIENT_ID: process.env.FACEBOOK_CLIENT_ID,
    FACEBOOK_CLIENT_SECRET: process.env.FACEBOOK_CLIENT_SECRET,
    GOOGLE_CLIENT_ID: process.env.GOOGLE_CLIENT_ID,
    GOOGLE_CLIENT_SECRET: process.env.GOOGLE_CLIENT_SECRET,
  },
  // runtime, server, ssr client, public, don't need to recompile app
  // server and getServersideProps pages/components
  publicRuntimeConfig: {},
};
