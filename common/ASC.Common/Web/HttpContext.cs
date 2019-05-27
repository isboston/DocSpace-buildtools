﻿using ASC.Common.DependencyInjection;
using Microsoft.AspNetCore.Http;

namespace ASC.Common
{
    public static class HttpContext
    {
        private static IHttpContextAccessor m_httpContextAccessor;

        public static void Configure(IHttpContextAccessor httpContextAccessor)
        {
            m_httpContextAccessor = httpContextAccessor;
            CommonServiceProvider.Current = httpContextAccessor.HttpContext.RequestServices;
        }

        public static Microsoft.AspNetCore.Http.HttpContext Current
        {
            get
            {
                return m_httpContextAccessor.HttpContext;
            }
        }
    }
}