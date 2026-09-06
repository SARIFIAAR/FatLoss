FROM node:22-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev
COPY server.js firestore.js admin.html ./
EXPOSE 8080
CMD ["node", "server.js"]
