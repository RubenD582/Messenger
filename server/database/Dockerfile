FROM node:16
WORKDIR /usr/src/app
# Copy package.json from context (which is the server directory)
COPY package.json ./
RUN npm install
# Copy just what we need from the database directory
COPY database/ ./
ENV DB_HOST=${DB_HOST}
ENV DB_USER=${DB_USER}
ENV DB_PASSWORD=${DB_PASSWORD}
ENV DB_NAME=${DB_NAME}
ENV DB_PORT=${DB_PORT}
CMD ["npx", "knex", "migrate:latest", "--env", "development"]