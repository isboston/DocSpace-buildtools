import React, { lazy } from "react";
import { Route, Switch } from "react-router-dom";
import { withRouter } from "react-router";

const CustomizationSettings = lazy(() => import("../../sub-components/common/customization"));
const NotImplementedSettings = lazy(() => import("../../sub-components/notImplementedSettings"));
const AccessRight = lazy(() => import("../../sub-components/security/accessRights"));
class SectionBodyContent extends React.PureComponent {

  render() {
    return (
      <Switch>
        <Route
          exact
          path={[`${this.props.match.path}/common/customization`,`${this.props.match.path}/common`, this.props.match.path]}
          component={CustomizationSettings}
        />
        <Route
          exact
          path={`${this.props.match.path}/security/access-rights`}
          component={AccessRight}
        />

        <Route component={NotImplementedSettings} />
      </Switch>
    );
  };
};

export default withRouter(SectionBodyContent);