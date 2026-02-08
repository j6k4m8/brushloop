import { URL } from "node:url";
import type { IncomingMessage, ServerResponse } from "node:http";

export interface RequestContext {
  req: IncomingMessage;
  res: ServerResponse;
  url: URL;
  params: Record<string, string>;
}

export type RouteHandler = (context: RequestContext) => Promise<void> | void;

interface RouteRecord {
  method: string;
  pattern: string;
  segments: string[];
  handler: RouteHandler;
}

/**
 * Lightweight HTTP router with named path params.
 */
export class Router {
  private readonly routes: RouteRecord[] = [];

  register(method: string, pattern: string, handler: RouteHandler): void {
    this.routes.push({
      method: method.toUpperCase(),
      pattern,
      segments: splitPath(pattern),
      handler
    });
  }

  async dispatch(req: IncomingMessage, res: ServerResponse): Promise<boolean> {
    const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
    const pathname = url.pathname;
    const method = (req.method ?? "GET").toUpperCase();
    const pathSegments = splitPath(pathname);

    for (const route of this.routes) {
      if (route.method !== method) {
        continue;
      }

      const params = matchSegments(route.segments, pathSegments);
      if (!params) {
        continue;
      }

      await route.handler({ req, res, url, params });
      return true;
    }

    return false;
  }
}

function splitPath(pathname: string): string[] {
  return pathname.split("/").filter((item) => item.length > 0);
}

function matchSegments(routeSegments: string[], pathSegments: string[]): Record<string, string> | null {
  if (routeSegments.length !== pathSegments.length) {
    return null;
  }

  const params: Record<string, string> = {};

  for (let index = 0; index < routeSegments.length; index += 1) {
    const routeSegment = routeSegments[index];
    const pathSegment = pathSegments[index];
    if (!routeSegment || !pathSegment) {
      return null;
    }

    if (routeSegment.startsWith(":")) {
      params[routeSegment.slice(1)] = decodeURIComponent(pathSegment);
      continue;
    }

    if (routeSegment !== pathSegment) {
      return null;
    }
  }

  return params;
}
