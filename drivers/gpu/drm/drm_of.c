#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/component.h>
#include <linux/export.h>
#include <linux/list.h>
#include <linux/of_graph.h>
#include <drm/drmP.h>
#include <drm/drm_crtc.h>
#include <drm/drm_panel.h>
#include <drm/drm_of.h>

/**
 * drm_crtc_port_mask - find the mask of a registered CRTC by port OF node
 * @dev: DRM device
 * @port: port OF node
 *
 * Given a port OF node, return the possible mask of the corresponding
 * CRTC within a device's list of CRTCs.  Returns zero if not found.
 */
static uint32_t drm_crtc_port_mask(struct drm_device *dev,
				   struct device_node *port)
{
	unsigned int index = 0;
	struct drm_crtc *tmp;

	drm_for_each_crtc(tmp, dev) {
		if (tmp->port == port)
			return 1 << index;

		index++;
	}

	return 0;
}

/**
 * drm_of_find_possible_crtcs - find the possible CRTCs for an encoder port
 * @dev: DRM device
 * @port: encoder port to scan for endpoints
 *
 * Scan all endpoints attached to a port, locate their attached CRTCs,
 * and generate the DRM mask of CRTCs which may be attached to this
 * encoder.
 *
 * See Documentation/devicetree/bindings/graph.txt for the bindings.
 */
uint32_t drm_of_find_possible_crtcs(struct drm_device *dev,
				    struct device_node *port)
{
	struct device_node *remote_port, *ep;
	uint32_t possible_crtcs = 0;

	for_each_endpoint_of_node(port, ep) {
		if (!of_device_is_available(ep)) {
			of_node_put(ep);
			continue;
		}

		remote_port = of_graph_get_remote_port(ep);
		if (!remote_port) {
			of_node_put(ep);
			return 0;
		}

		possible_crtcs |= drm_crtc_port_mask(dev, remote_port);

		of_node_put(remote_port);
	}

	return possible_crtcs;
}
EXPORT_SYMBOL(drm_of_find_possible_crtcs);

/**
 * drm_of_component_probe - Generic probe function for a component based master
 * @dev: master device containing the OF node
 * @compare_of: compare function used for matching components
 * @master_ops: component master ops to be used
 *
 * Parse the platform device OF node and bind all the components associated
 * with the master. Interface ports are added before the encoders in order to
 * satisfy their .bind requirements
 * See Documentation/devicetree/bindings/graph.txt for the bindings.
 *
 * Returns zero if successful, or one of the standard error codes if it fails.
 */
int drm_of_component_probe(struct device *dev,
			   int (*compare_of)(struct device *, void *),
			   const struct component_master_ops *m_ops)
{
	struct device_node *ep, *port, *remote;
	struct component_match *match = NULL;
	int i;

	if (!dev->of_node)
		return -EINVAL;

	/*
	 * Bind the crtc's ports first, so that drm_of_find_possible_crtcs()
	 * called from encoder's .bind callbacks works as expected
	 */
	for (i = 0; ; i++) {
		port = of_parse_phandle(dev->of_node, "ports", i);
		if (!port)
			break;

		if (!of_device_is_available(port->parent)) {
			of_node_put(port);
			continue;
		}

		component_match_add(dev, &match, compare_of, port);
		of_node_put(port);
	}

	if (i == 0) {
		pr_err( "missing 'ports' property\n");
		return -ENODEV;
	}

	if (!match) {
		pr_err( "no available port\n");
		return -ENODEV;
	}

	/*
	 * For bound crtcs, bind the encoders attached to their remote endpoint
	 */
	for (i = 0; ; i++) {
		port = of_parse_phandle(dev->of_node, "ports", i);
		if (!port)
			break;

		if (!of_device_is_available(port->parent)) {
			of_node_put(port);
			continue;
		}

		for_each_child_of_node(port, ep) {
			remote = of_graph_get_remote_port_parent(ep);
			if (!remote || !of_device_is_available(remote)) {
				of_node_put(remote);
				continue;
			} else if (!of_device_is_available(remote->parent)) {
				pr_err( "parent device of %s is not available\n",
					 remote->full_name);
				of_node_put(remote);
				continue;
			}

			component_match_add(dev, &match, compare_of, remote);
			of_node_put(remote);
		}
		of_node_put(port);
	}

	return component_master_add_with_match(dev, m_ops, match);
}
EXPORT_SYMBOL(drm_of_component_probe);

/*
 * drm_of_encoder_active_endpoint - return the active encoder endpoint
 * @node: device tree node containing encoder input ports
 * @encoder: drm_encoder
 *
 * Given an encoder device node and a drm_encoder with a connected crtc,
 * parse the encoder endpoint connecting to the crtc port.
 */
int drm_of_encoder_active_endpoint(struct device_node *node,
				   struct drm_encoder *encoder,
				   struct of_endpoint *endpoint)
{
	struct device_node *ep;
	struct drm_crtc *crtc = encoder->crtc;
	struct device_node *port;
	int ret;

	if (!node || !crtc)
		return -EINVAL;

	for_each_endpoint_of_node(node, ep) {
		port = of_graph_get_remote_port(ep);
		of_node_put(port);
		if (port == crtc->port) {
			ret = of_graph_parse_endpoint(ep, endpoint);
			of_node_put(ep);
			return ret;
		}
	}

	return -EINVAL;
}
EXPORT_SYMBOL_GPL(drm_of_encoder_active_endpoint);

/*
 * drm_of_find_panel_or_bridge - return connected panel or bridge device
 * @np: device tree node containing encoder output ports
 * @panel: pointer to hold returned drm_panel
 * @bridge: pointer to hold returned drm_bridge
 *
 * Given a DT node's port and endpoint number, find the connected node and
 * return either the associated struct drm_panel or drm_bridge device. Either
 * @panel or @bridge must not be NULL.
 *
 * Returns zero if successful, or one of the standard error codes if it fails.
 */
int drm_of_find_panel_or_bridge(const struct device_node *np,
				int port, int endpoint,
				struct drm_panel **panel,
				struct drm_bridge **bridge)
{
	int ret = -EPROBE_DEFER;
	struct device_node *remote;

	if (np != NULL)
		pr_err("%s: for node: %s\n", __func__, np->full_name);
	else
		pr_err("np is NULL\n");

	if (!panel && !bridge) {
		pr_err("%s: no panel or bridge found\n", __func__);
		return -EINVAL;
	}

	if (panel)
		*panel = NULL;

	pr_err("%s: %pOF\n", __func__, np);
	pr_err("%s: [PORTS = %p]\n", __func__, of_get_child_by_name(np, "ports"));
	pr_err("%s: [PORT = %p]\n", __func__, of_get_child_by_name(np, "port"));

	/**
	 * Some OF graphs don't require 'ports' to represent the downstream
	 * panel or bridge; instead it simply adds a child node on a given
	 * parent node.
	 *
	 * Lookup that child node for a given parent however that child
	 * cannot be a 'port' alone or it cannot be a 'port' node too.
	 */
	if (!of_get_child_by_name(np, "ports")) {
		pr_err("1: [np %s] [port count %d]\n", np->name, of_get_child_count(np));
		if (of_get_child_by_name(np, "port") && (of_get_child_count(np) == 1))
			goto of_graph_get_remote;

		for_each_available_child_of_node(np, remote) {
			pr_err("2: [np -> %s] [remote -> %s]\n",
				np->name, remote->name);
			if (of_node_name_eq(remote, "port"))
				continue;

			pr_err("3: [np -> %s] [remote -> %s]\n",
				np->name, remote->name);
			goto of_find_panel_or_bridge;
		}
	}

of_graph_get_remote:
	/*
	 * of_graph_get_remote_node() produces a noisy error message if port
	 * node isn't found and the absence of the port is a legit case here,
	 * so at first we silently check whether graph presents in the
	 * device-tree node.
	 */
	if (!of_graph_is_present(np)) {
		pr_err("%s: no graph found in %s\n", __func__, np->full_name);
		return -ENODEV;
	}

	remote = of_graph_get_remote_node(np, port, endpoint);

of_find_panel_or_bridge:
	if (!remote) {
		pr_err("%s: no remote node found\n", __func__);
		return -ENODEV;
	}

	if (panel) {
		pr_err("%s: panel found: ret -> %d\n",
			__func__, ret);
		*panel = of_drm_find_panel(remote);
		if (*panel) {
			ret = 0;
			pr_err("panel found now setting ret = 0\n");
		} else {
			*panel = NULL;
			pr_err("panel not found now setting panel = NULL\n");
		}
	} else {
		pr_err("%s: no panel found :(", __func__);
	}

	/* No panel found yet, check for a bridge next. */
	if (bridge) {
		pr_err("%s: bridge found: ret -> %d\n",
			__func__, ret);
		if (ret) {
			*bridge = of_drm_find_bridge(remote);
			if (*bridge) {
				pr_err("bridge found now setting ret = 0\n");
				ret = 0;
			}
		} else {
			pr_err("bridge not found now setting bridge = NULL\n");
				*bridge = NULL;
		}
	} else {
		pr_err("%s: No bridge found\n", __func__);
	}

	pr_err("%s: putting remote name: %s\n", __func__, remote->name);
	of_node_put(remote);

	pr_err("%s returned: %d\n", __func__, ret);
	return ret;
}
EXPORT_SYMBOL_GPL(drm_of_find_panel_or_bridge);
